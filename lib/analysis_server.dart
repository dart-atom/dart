// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Wrapper over the analysis server providing a simplified API and automatic
/// handling of reliability.
library atom.analysis_server;

import 'dart:async';

import 'package:logging/logging.dart';

import 'atom.dart';
import 'projects.dart';
import 'sdk.dart';
import 'state.dart';
import 'utils.dart';
import 'impl/analysis_server_impl.dart';

final Logger _logger = new Logger('analysis-server');

class AnalysisServer implements Disposable {
  StreamSubscriptions subs = new StreamSubscriptions();
  Disposables disposables = new Disposables();

  Server _server;

  List<DartProject> knownRoots = [];

  AnalysisServer() {
    Timer.run(_setup);
  }

  _setup() async {
    _logger.fine('setup()');

    subs.add(projectManager.onChanged.listen(_reconcileRoots));
    subs.add(sdkManager.onSdkChange.listen(_handleSdkChange));

    disposables.add(atom.workspace.observeTextEditors(_handleNewEditor));

    // Init server and warmup
    _server = new Server(sdkManager.sdk);
    _logger.finer('Server ctor done');

    await _server.setup();

    _logger.finer('setup() done');
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

  /// Tell the analysis server a file should be included in analysis.
  void watchRoots(List<String> paths) {
     _logger.finer('watchRoots(): ${paths}');

    if (isActive) {
      // TODO:

    }
  }

  /// Tell the analysis server a file should not be included in analysis.
  void unwatchRoots(List<String> paths) {
     _logger.finer('unwatchRoots(): ${paths}');

    if (isActive) {
      // TODO:

    }
  }

  /// Force recycle of the analysis server.
  // TODO: Call Reset on the wrapper
  void forceReset() => null;

  // TOOD: Send shutdown
  // Dispose wrapper
  void dispose() {
    _logger.fine('dispose()');

    subs.cancel();
    disposables.dispose();
  }

  void _reconcileRoots(List<DartProject> currentProjects) {
    Set oldSet = new Set.from(knownRoots);
    Set currentSet = new Set.from(currentProjects);

    Set addedProjects = currentSet.difference(oldSet);
    Set removedProjects = oldSet.difference(currentSet);

    if (removedProjects.isNotEmpty) {
      unwatchRoots(removedProjects.map((p) => p.path).toList());
    }

    if (addedProjects.isNotEmpty) {
      watchRoots(addedProjects.map((p) => p.path).toList());

      List<TextEditor> editors = atom.workspace.getTextEditors().toList();

      for (DartProject addedProject in addedProjects) {
        for (TextEditor editor in editors) {
          if (addedProject.contains(editor.getPath())) {
            _handleNewEditor(editor);
          }
        }
      }
    }

    knownRoots = currentProjects;
  }

  void _handleSdkChange(Sdk newSdk) {
    // TODO:
     _logger.finer('_handleSdkChange(): ${newSdk}');
  }

  void _handleNewEditor(TextEditor editor) {
    final String path = editor.getPath();

    // is in a dart project
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return;

    // is a dart file
    if (!project.isDartFile(path)) return;

    // TODO: `onDidStopChanging` will notify when the file has been opened, even
    // if it has not been modified.
    editor.onDidStopChanging.listen(
        (_) => notifyFileChanged(path, editor.getText()));

    editor.onDidDestroy.listen((_) => notifyFileChanged(path, null));
  }
}
