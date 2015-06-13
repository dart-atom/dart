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

// TODO: Given a File or path, return the cooresponding Dart project.

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

  final List<DartProject> projects = [];

  ProjectManager() {
    _sub = atom.project.onDidChangePaths.listen((_) => _checkForNewRemovedProjects());
    Timer.run(rescanForProjects);
  }

  bool get hasDartProjects => projects.isNotEmpty;

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

  void _checkForNewRemovedProjects() {
    Set<Directory> previousDirs = new Set.from(projects.map((p) => p.directory));
    Set<Directory> currentDirs = new Set.from(atom.project.getDirectories());

    Set<Directory> removedDirs = previousDirs.difference(currentDirs);
    Set<Directory> addedDirs = currentDirs.difference(previousDirs);

    if (removedDirs.isNotEmpty) {
      _handleRemovedDirs(removedDirs.toList());
    }

    if (addedDirs.isNotEmpty) {
      _handleAddedDirs(addedDirs.toList());
    }
  }

  void _handleRemovedDirs(List<Directory> dirs) {
    bool removed = false;

    dirs.forEach((Directory dir) {
      for (DartProject project in projects) {
        if (dir == project.directory || dir.contains(project.directory.path)) {
          projects.remove(project);
          removed = true;
          break;
        }
      }
    });

    if (removed) {
      _logger.fine('${projects}');
      _controller.add(projects);
    }
  }

  void _handleAddedDirs(List<Directory> dirs) {
    int count = projects.length;

    dirs.forEach((Directory dir) {
      _findDartProjects(dir, _recurse_depth).forEach((dir) {
        projects.add(new DartProject(dir));
      });
    });

    if (count != projects.length) {
      _logger.fine('${projects}');
      _controller.add(projects);
    }
  }

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

class DartProject {
  final Directory directory;

  DartProject(this.directory);

  String get path => directory.path;

  int get hashCode => directory.hashCode;

  operator==(other) => other is DartProject && directory == other.directory;

  String toString() => '[Project ${directory.getBaseName()}]';
}

class ProjectScanJob extends Job {
  ProjectScanJob() : super('Scanning for new Dart Projects');

  Future run() {
    projectManager.rescanForProjects();
    return new Future.delayed(new Duration(seconds: 1));
  }
}
