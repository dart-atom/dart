// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Wrapper over the analysis server providing a simplified API and automatic
/// handling of reliability.
library atom.analysis_server;

import 'dart:async';

import 'package:logging/logging.dart';

import 'atom.dart';
import 'jobs.dart';
import 'projects.dart';
import 'sdk.dart';
import 'state.dart';
import 'utils.dart';
import 'impl/analysis_server_impl.dart';

final Logger _logger = new Logger('analysis-server');

class AnalysisServer implements Disposable {
  StreamSubscriptions subs = new StreamSubscriptions();
  Disposables disposables = new Disposables();

  StreamController<bool> _serverActiveController =
      new StreamController.broadcast();
  StreamController<bool> _serverBusyController =
      new StreamController.broadcast();

  Server _server;
  _AnalyzingJob _job;

  List<DartProject> knownRoots = [];

  AnalysisServer() {
    Timer.run(_setup);
  }

  Stream<bool> get onActive => _serverActiveController.stream;

  Stream<bool> get onBusy => _serverBusyController.stream;

  void _setup() {
    _logger.fine('setup()');

    subs.add(projectManager.onChanged.listen(_reconcileRoots));
    subs.add(sdkManager.onSdkChange.listen(_handleSdkChange));

    disposables.add(atom.workspace.observeTextEditors(_handleNewEditor));

    knownRoots = projectManager.projects.toList();

    _checkTrigger();
  }

  /// Returns whether the analysis server is active and running.
  bool get isActive => _server != null;

  /// Provides an instantaneous snapshot of the known issues and warnings.
  List<AnalysisIssue> get issues => null;

  /// Subscribe to this to get told when the issues list has changed.
  Stream get issuesUpdatedNotification => null;

  // /// Compute completions for a given location.
  // List<Completion> computeCompletions(String sourcePath, int offset) => null;

  /// Tell the analysis server a file has changed in memory.
  void notifyFileChanged(String path, String contents) {
    _logger.finer('notifyFileChanged(): ${path}');

    if (isActive) {
      // TODO (lukechurch): Send this as a sendAddOverlays command

    }
  }

  void _syncRoots() {
    if (isActive) {
      List<String> roots = knownRoots.map((dir) => dir.path).toList();
      _server.sendAnalysisSetAnalysisRoots(roots, []);
    }
  }

  /// Force recycle of the analysis server.
  // TODO: Call Reset on the wrapper
  void forceReset() => null;

  void dispose() {
    _logger.fine('dispose()');

    _checkTrigger(dispose: true);

    subs.cancel();
    disposables.dispose();
  }

  void _reconcileRoots(List<DartProject> currentProjects) {
    Set oldSet = new Set.from(knownRoots);
    Set currentSet = new Set.from(currentProjects);

    Set addedProjects = currentSet.difference(oldSet);
    Set removedProjects = oldSet.difference(currentSet);

    knownRoots = currentProjects;

    if (removedProjects.isNotEmpty || addedProjects.isNotEmpty) {
      _syncRoots();
    }

    if (addedProjects.isNotEmpty) {
      List<TextEditor> editors = atom.workspace.getTextEditors().toList();

      for (DartProject addedProject in addedProjects) {
        for (TextEditor editor in editors) {
          if (addedProject.contains(editor.getPath())) {
            _handleNewEditor(editor);
          }
        }
      }
    }

    _checkTrigger();
  }

  void _handleSdkChange(Sdk newSdk) {
    _checkTrigger();
  }

  void _handleNewEditor(TextEditor editor) {
    final String path = editor.getPath();

    // If it's in a dart project.
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return;

    // And it's a dart file.
    if (!project.isDartFile(path)) return;

    // TODO: `onDidStopChanging` will notify when the file has been opened, even
    // if it has not been modified.
    editor.onDidStopChanging
        .listen((_) => notifyFileChanged(path, editor.getText()));

    editor.onDidDestroy.listen((_) => notifyFileChanged(path, null));
  }

  void _checkTrigger({bool dispose: false}) {
    bool shouldBeRunning = knownRoots.isNotEmpty && sdkManager.hasSdk;

    if (dispose || (!shouldBeRunning && _server != null)) {
      // shutdown
      _server.kill();
    } else if (shouldBeRunning && _server == null) {
      // startup
      Server server = new Server(sdkManager.sdk);
      _server = server;
      _initNewServer(server);
    }
  }

  void _initNewServer(Server server) {
    // _AnalyzingJob
    server.onBusy.listen((value) => _serverBusyController.add(value));
    server.whenDisposed.then((exitCode) => _handleServerDeath(server));
    onBusy.listen((busy) {
      if (!busy && _job != null) {
        _job.finish();
        _job = null;
      } else if (busy && _job == null) {
        _job = new _AnalyzingJob()..start();
      }
    });
    server.setup().then((_) {
      _serverActiveController.add(true);
      _syncRoots();
    });
  }

  void _handleServerDeath(Server server) {
    if (_server == server) {
      _server = null;

      _serverActiveController.add(false);
      _serverBusyController.add(false);
    }
  }
}

class _AnalyzingJob extends Job {
  static const Duration _debounceDelay = const Duration(milliseconds: 150);

  Completer completer = new Completer();

  _AnalyzingJob() : super('Analyzing');

  bool get quiet => true;

  Future run() => completer.future;

  void start() {
    // Debounce the analysis busy event.
    new Timer(_debounceDelay, () {
      if (!completer.isCompleted) schedule();
    });
  }

  void finish() {
    if (!completer.isCompleted) completer.complete();
  }
}
