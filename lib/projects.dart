// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library to simplify locating Dart projects in Atom.
library atom.projects;

import 'dart:async';

import 'package:logging/logging.dart';

import 'atom.dart';
import 'jobs.dart';
import 'state.dart';
import 'utils.dart';
import 'impl/pub.dart' as pub;

final Logger _logger = new Logger('projects');

/// A class to locate Dart projects in Atom and listen for new or removed Dart
/// projects.
class ProjectManager implements Disposable {
  static const int _recurse_depth = 2;

  /// Return whether the given directory is a Dart project.
  static bool isDartProject(Directory dir) {
    if (dir.getFile(pub.pubspecFileName).existsSync()) return true;
    if (dir.getFile('.packages').existsSync()) return true;
    return false;
  }

  StreamController<List<DartProject>> _controller = new StreamController.broadcast();
  StreamSubscription _sub;

  final Map<String, StreamSubscription> _directoryListeners = {};

  final List<DartProject> projects = [];

  ProjectManager() {
    _sub = atom.project.onDidChangePaths.listen(_handleProjectPathsChanged);
    Timer.run(() {
      rescanForProjects();
      _updateChangeListeners(atom.project.getPaths());
    });
  }

  bool get hasDartProjects => projects.isNotEmpty;

  /// Return the dart project that contains the given path, or `null` if there
  /// is no such project.
  DartProject getProjectFor(String path) {
    for (DartProject project in projects) {
      Directory dir = project.directory;
      if (dir.path == path || dir.contains(path)) return project;
    }

    return null;
  }

  /// Do a full re-scan for Dart projects. This can find new projects if the
  /// file system has changed since Atom was opened.
  ///
  /// Calling this method will cause `onChanged` event to be fired if project
  /// changes are found.
  void rescanForProjects() => _fullScanForProjects();

  Stream<List<DartProject>> get onChanged => _controller.stream;

  void dispose() {
    _logger.fine('dispose()');

    _sub.cancel();
    _directoryListeners.values.forEach((StreamSubscription sub) => sub.cancel());
  }

  void _fullScanForProjects() {
    bool changed = false;

    Set<Directory> previousDirs = new Set.from(projects.map((p) => p.directory));

    Set<Directory> allDirs = new Set();
    for (Directory dir in atom.project.getDirectories()) {
      allDirs.addAll(_findDartProjects(dir, _recurse_depth));
    }

    for (Directory dir in previousDirs) {
      if (!allDirs.contains(dir)) {
        changed = true;
        projects.removeWhere((p) => p.directory == dir);
      }
    }

    Set<Directory> newDirs = allDirs.difference(previousDirs);
    if (newDirs.isNotEmpty) changed = true;
    projects.addAll(newDirs.map((dir) => new DartProject(dir)));

    if (changed) {
      _logger.fine('${projects}');
      _controller.add(projects);
    }
  }

  void _handleProjectPathsChanged(List<String> allPaths) {
    _updateChangeListeners(allPaths);
    _checkForNewRemovedProjects();
  }

  _updateChangeListeners(List<String> allPaths) {
    Set<String> previousPaths = new Set.from(_directoryListeners.keys);
    Set<String> currentPaths = new Set.from(allPaths);

    Set<String> removedPaths = previousPaths.difference(currentPaths);
    Set<String> addedPaths = currentPaths.difference(previousPaths);

    for (String removedPath in removedPaths) {
      StreamSubscription sub = _directoryListeners.remove(removedPath);
      sub.cancel();
    }

    for (String addedPath in addedPaths) {
      Directory dir = new Directory.fromPath(addedPath);
      _directoryListeners[addedPath] = dir.onDidChange.listen(
          (_) => _handleDirectoryChanged(dir));
    }
  }

  void _handleDirectoryChanged(Directory dir) {
    bool currentProjectDir = projects.any(
        (DartProject project) => project.directory == dir);
    if (currentProjectDir != isDartProject(dir)) {
      _fullScanForProjects();
    }
  }

  void _checkForNewRemovedProjects() {
    _fullScanForProjects();
    // // FIXME: p.directory isn't the same as project.getDirectories().
    // Set<Directory> previousDirs = new Set.from(projects.map((p) => p.directory));
    // Set<Directory> currentDirs = new Set.from(atom.project.getDirectories());
    //
    // Set<Directory> removedDirs = previousDirs.difference(currentDirs);
    // Set<Directory> addedDirs = currentDirs.difference(previousDirs);
    //
    // if (removedDirs.isNotEmpty) {
    //   _handleRemovedDirs(removedDirs.toList());
    // }
    //
    // if (addedDirs.isNotEmpty) {
    //   _handleAddedDirs(addedDirs.toList());
    // }
  }

  // void _handleRemovedDirs(List<Directory> dirs) {
  //   bool removed = false;
  //
  //   dirs.forEach((Directory dir) {
  //     for (DartProject project in projects) {
  //       if (dir == project.directory || dir.contains(project.directory.path)) {
  //         projects.remove(project);
  //         removed = true;
  //         break;
  //       }
  //     }
  //   });
  //
  //   if (removed) {
  //     _logger.fine('${projects}');
  //     _controller.add(projects);
  //   }
  // }

  // void _handleAddedDirs(List<Directory> dirs) {
  //   int count = projects.length;
  //
  //   dirs.forEach((Directory dir) {
  //     _findDartProjects(dir, _recurse_depth).forEach((dir) {
  //       projects.add(new DartProject(dir));
  //     });
  //   });
  //
  //   if (count != projects.length) {
  //     _logger.fine('${projects}');
  //     _controller.add(projects);
  //   }
  // }

  List<Directory> _findDartProjects(Directory dir, int recurse) {
    if (isDartProject(dir)) {
      return [dir];
    } else if (recurse > 0) {
      List<Directory> found = [];
      for (Entry entry in dir.getEntriesSync()) {
        if (entry.isDirectory()) {
          found.addAll(_findDartProjects(entry, recurse - 1));
        }
      }
      return found;
    } else {
      return [];
    }
  }
}

/// A representation of a Dart project; a directory with a `pubspec.yaml` file
/// or a `.packages` file.
class DartProject {
  final Directory directory;

  DartProject(this.directory);

  String get path => directory.path;

  int get hashCode => directory.hashCode;

  bool isDartFile(String path) {
    if (path == null) return false;
    return path.endsWith('.dart');
  }

  bool contains(String path) => directory.contains(path);

  operator==(other) => other is DartProject && directory == other.directory;

  String toString() => '[Project ${directory.getBaseName()}]';
}

class ProjectScanJob extends Job {
  ProjectScanJob() : super('Refresh Dart project list');

  Future run() {
    projectManager.rescanForProjects();
    return new Future.delayed(new Duration(seconds: 1));
  }
}
