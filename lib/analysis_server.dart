// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Wrapper over the analysis server providing a simplified API and automatic
/// handling of reliability.
library atom.analysis_server;

import 'dart:async';

import 'package:logging/logging.dart';

import 'atom.dart';
import 'atom_linter.dart';
import 'dependencies.dart';
import 'jobs.dart';
import 'projects.dart';
import 'sdk.dart';
import 'state.dart';
import 'utils.dart';
import 'impl/analysis_server_dialog.dart';
import 'impl/analysis_server_impl.dart';

export 'impl/analysis_server_impl.dart'
    show AnalysisErrorsResult, AnalysisError, RequestError;

final Logger _logger = new Logger('analysis-server');

class AnalysisServer implements Disposable {
  StreamSubscriptions subs = new StreamSubscriptions();
  Disposables disposables = new Disposables();

  StreamController<bool> _serverActiveController =
      new StreamController.broadcast();
  StreamController<bool> _serverBusyController =
      new StreamController.broadcast();
  StreamController<String> _allMessagesController =
      new StreamController.broadcast();

  Server _server;
  _AnalyzingJob _job;

  List<DartProject> knownRoots = [];

  AnalysisServer() {
    // Register the linter provider.
    new _DartLinterProvider().register();

    // onActive.listen((val) => _logger.info('analysis server active: ${val}'));
    // onBusy.listen((val) => _logger.info('analysis server busy: ${val}'));

    Timer.run(_setup);
  }

  Stream<bool> get onActive => _serverActiveController.stream;

  Stream<bool> get onBusy => _serverBusyController.stream;

  Stream<String> get onAllMessages => _allMessagesController.stream;

  void _setup() {
    _logger.fine('setup()');

    subs.add(projectManager.onChanged.listen(_reconcileRoots));
    subs.add(sdkManager.onSdkChange.listen(_handleSdkChange));

    disposables.add(atom.workspace.observeTextEditors(_handleNewEditor));

    knownRoots = projectManager.projects.toList();

    _checkTrigger();

    // Create the analysis server diagnostics dialog.
    disposables.add(deps[AnalysisServerDialog] = new AnalysisServerDialog());

    disposables.add(atom.commands.add('atom-text-editor', 'dart-lang:dartdoc',
        (event) {
      if (_server == null) return;

      bool explicit = true;

      TextEditor editor = event.editor;
      Range range = editor.getSelectedBufferRange();
      int offset = editor.getBuffer().characterIndexForPosition(range.start);
      _server
          .analysis_getHover(editor.getPath(), offset)
          .then((HoverResult result) {
        if (result.hovers.isEmpty) {
          if (explicit) atom.beep();
          return;
        }

        HoverInformation hover = result.hovers.first;
        atom.notifications.addInfo(hover.title(),
            dismissable: true, detail: hover.render());
      });
    }));
  }

  /// Returns whether the analysis server is active and running.
  bool get isActive => _server != null;

  bool get isBusy => _server != null && _server.isBusy;

  /// Subscribe to this to get told when the issues list has changed.
  Stream get issuesUpdatedNotification => null;

  // /// Compute completions for a given location.
  // List<Completion> computeCompletions(String sourcePath, int offset) => null;

  Future<AnalysisErrorsResult> getErrors(String filePath) {
    if (isActive) {
      return _server.analysis_getErrors(filePath);
    } else {
      return new Future.value(new AnalysisErrorsResult.empty());
    }
  }

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
      _server.analysis_setAnalysisRoots(roots, []);
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

  /// Explictely and manually start the analysis server. This will not succeed
  /// if there is no SDK.
  void start() {
    if (!sdkManager.hasSdk) return;

    if (_server == null) {
      Server server = new Server(sdkManager.sdk);
      _server = server;
      _initNewServer(server);
    }
  }

  /// If an analysis server is running, terminate it.
  void shutdown() {
    if (_server != null) _server.kill();
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
    server.onBusy.listen((value) => _serverBusyController.add(value));
    server.whenDisposed.then((exitCode) => _handleServerDeath(server));
    server.onAllMessages
        .listen((message) => _allMessagesController.add(message));

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
  Function _infoAction;

  _AnalyzingJob() : super('Analyzing') {
    _infoAction = () {
      deps[AnalysisServerDialog].showDialog();
    };
  }

  bool get quiet => true;

  Function get infoAction => _infoAction;

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

class _DartLinterProvider extends LinterProvider {
  // TODO: Options are 'file' and 'project' scope, and lintOnFly true or false.
  _DartLinterProvider() : super(grammarScopes: ['source.dart'], scope: 'file');

  void register() =>
      LinterProvider.registerLinterProvider('provideLinter', this);

  Future<List<LintMessage>> lint(TextEditor editor) {
    String filePath = editor.getPath();
    return analysisServer
        .getErrors(filePath)
        .then((AnalysisErrorsResult result) {
      return result.errors.where((AnalysisError error) {
        return error.severity == 'WARNING' || error.severity == 'ERROR';
      }).map((e) => _cvtMessage(filePath, e)).toList();
    }).catchError((e) {
      print(e);
      return [];
    });
  }

  final Map<String, String> _severityMap = {
    'ERROR': LintMessage.ERROR,
    'WARNING': LintMessage.WARNING
    //'INFO': LintMessage.INFO
  };

  LintMessage _cvtMessage(String filePath, AnalysisError error) {
    return new LintMessage(
        type: _severityMap[error.severity],
        text: error.message,
        filePath: filePath,
        range: _cvtLocation(error.location));
  }

  Rn _cvtLocation(Location location) {
    return new Rn(new Pt(location.startLine - 1, location.startColumn),
        new Pt(location.startLine - 1, location.startColumn + location.length));
  }
}
