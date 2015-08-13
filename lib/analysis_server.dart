// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Wrapper over the analysis server providing a simplified API and automatic
/// handling of reliability.
library atom.analysis_server;

import 'dart:async';

import 'package:frappe/frappe.dart';
import 'package:logging/logging.dart';

import 'analysis/analysis_server_dialog.dart';
import 'analysis/analysis_server_gen.dart';
import 'atom.dart';
import 'dependencies.dart';
import 'jobs.dart';
import 'process.dart';
import 'projects.dart';
import 'sdk.dart';
import 'state.dart';
import 'utils.dart';

export 'analysis/analysis_server_gen.dart' show FormatResult, HoverInformation,
    HoverResult, RequestError, AvailableRefactoringsResult, RefactoringResult,
    RefactoringOptions, SourceFileEdit;

final Logger _logger = new Logger('analysis-server');

class AnalysisServer implements Disposable {
  static bool get startWithDebugging => atom.config.getValue('${pluginId}.debugAnalysisServer');

  static final int OBSERVATORY_PORT = 23071;
  static final int DIAGNOSTICS_PORT = 23072;

  static String get observatoryUrl => 'http://localhost:${OBSERVATORY_PORT}/';
  static String get diagnosticsUrl => 'http://localhost:${DIAGNOSTICS_PORT}/';

  StreamSubscriptions subs = new StreamSubscriptions();
  Disposables disposables = new Disposables();

  StreamController<bool> _serverActiveController = new StreamController.broadcast();
  StreamController<bool> _serverBusyController = new StreamController.broadcast();
  StreamController<String> _onSendController = new StreamController.broadcast();
  StreamController<String> _onReceiveController = new StreamController.broadcast();
  StreamController<AnalysisNavigation> _onNavigatonController = new StreamController.broadcast();

  _AnalysisServerWrapper _server;
  _AnalyzingJob _job;

  List<DartProject> knownRoots = [];

  Property<bool> isActiveProperty;

  AnalysisServer() {
    isActiveProperty = new Property.fromStreamWithInitialValue(false, onActive);
    Timer.run(_setup);

    bool firstNotification = true;

    onActive.listen((value) {
      if (firstNotification) {
        firstNotification = false;
        return;
      }

      if (value) {
        atom.notifications.addInfo('Analysis server running.');
      } else {
        atom.notifications.addWarning('Analysis server terminated.');
      }
    });
  }

  Stream<bool> get onActive => _serverActiveController.stream;
  Stream<bool> get onBusy => _serverBusyController.stream;

  Stream<String> get onSend => _onSendController.stream;
  Stream<String> get onReceive => _onReceiveController.stream;

  Stream<AnalysisNavigation> get onNavigaton => _onNavigatonController.stream;

  Stream<AnalysisErrors> get onAnalysisErrors =>
      analysisServer._server.analysis.onErrors;
  Stream<AnalysisFlushResults> get onAnalysisFlushResults =>
    analysisServer._server.analysis.onFlushResults;

  Server get server => _server;

  void _setup() {
    subs.add(projectManager.onChanged.listen(_reconcileRoots));
    subs.add(sdkManager.onSdkChange.listen(_handleSdkChange));

    editorManager.dartProjectEditors.onActiveEditorChanged.listen(_focusedEditorChanged);

    knownRoots.clear();
    knownRoots.addAll(projectManager.projects);

    _checkTrigger();

    // Create the analysis server diagnostics dialog.
    disposables.add(deps[AnalysisServerDialog] = new AnalysisServerDialog());

    onSend.listen((String message)    => _logger.finer('--> ${message}'));
    onReceive.listen((String message) => _logger.finer('<-- ${message}'));
  }

  /// Returns whether the analysis server is active and running.
  bool get isActive => _server != null && _server.isRunning;

  bool get isBusy => _server != null && _server.analyzing;

  /// Subscribe to this to get told when the issues list has changed.
  Stream get issuesUpdatedNotification => null;

  Future<ErrorsResult> getErrors(String filePath) {
    if (isActive) {
      return _server.analysis.getErrors(filePath);
    } else {
      return new Future.value(new ErrorsResult([]));
    }
  }

  void _syncRoots() {
    if (isActive) {
      List<String> roots = knownRoots.map((dir) => dir.path).toList();
      _logger.fine("setAnalysisRoots(${roots})");
      _server.analysis.setAnalysisRoots(roots, []);
    }
  }

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

    // Create a copy of the list.
    knownRoots.clear();
    knownRoots.addAll(currentProjects);

    if (removedProjects.isNotEmpty) {
      _logger.fine("removed: ${removedProjects}");
      removedProjects.forEach(
        (project) => errorRepository.clearForDirectory(project.directory));
    }

    if (addedProjects.isNotEmpty) _logger.fine("added: ${addedProjects}");

    if (removedProjects.isNotEmpty || addedProjects.isNotEmpty) {
      _syncRoots();
    }

    _checkTrigger();
  }

  void _handleSdkChange(Sdk newSdk) {
    _checkTrigger();
  }

  void _focusedEditorChanged(TextEditor editor) {
    if (!isActive || editor == null) return;

    String path = editor.getPath();

    if (path != null) {
      // TODO: What a truly interesting API.
      _server.analysis.setSubscriptions({'NAVIGATION': [path]});

      // Ensure that the path is in a Dart project.
      if (projectManager.getProjectFor(path) != null) {
        server.analysis.setPriorityFiles([path]).catchError((e) {
          _logger.warning('Error from setPriorityFiles()', e);
        });
      }
    }
  }

  /// Explicitly and manually start the analysis server. This will not succeed
  /// if there is no SDK.
  void start() {
    if (!sdkManager.hasSdk) return;

    if (_server == null) {
      _AnalysisServerWrapper server = _AnalysisServerWrapper.create(sdkManager.sdk);
      _server = server;
      _initNewServer(server);
    } else if (!_server.isRunning) {
      _server.restart(sdkManager.sdk);
      _initExistingServer(_server);
    }
  }

  /// Reanalyze the world.
  void reanalyzeSources() {
    if (isActive) _server.analysis.reanalyze();
  }

  Stream<SearchResult> filterSearchResults(String id) {
    StreamSubscription sub;
    StreamController controller = new StreamController(
        onCancel: () => sub.cancel());

    sub = server.search.onResults.listen((SearchResults result) {
      if (id == result.id && !controller.isClosed) {
        for (SearchResult r in result.results) {
          controller.add(r);
        }

        if (result.isLast) {
          sub.cancel();
          controller.close();
        }
      }
    });

    return controller.stream;
  }

  Future<FormatResult> format(String path, int selectionOffset, int selectionLength,
      {int lineLength}) {
    return server.edit.format(
        path, selectionOffset, selectionLength, lineLength: lineLength);
  }

  Future<AvailableRefactoringsResult> getAvailableRefactorings(
      String path, int offset, int length) {
    return server.edit.getAvailableRefactorings(path, offset, length);
  }

  Future<RefactoringResult> getRefactoring(
      String kind, String path, int offset, int length, bool validateOnly,
      {RefactoringOptions options}) {
    return server.edit.getRefactoring(kind, path, offset, length, validateOnly,
        options: options);
  }

  Future<FixesResult> getFixes(String path, int offset) {
    return server.edit.getFixes(path, offset);
  }

  Future<HoverResult> getHover(String file, int offset) =>
      server.analysis.getHover(file, offset);

  Future<FindElementReferencesResult> findElementReferences(
      String path, int offset, bool includePotential) {
    return server.search.findElementReferences(path, offset, includePotential);
  }

  Future<TypeHierarchyResult> getTypeHierarchy(String path, int offset) =>
      server.search.getTypeHierarchy(path, offset);

  /// If an analysis server is running, terminate it.
  void shutdown() {
    if (_server != null) _server.kill();
  }

  void _checkTrigger({bool dispose: false}) {
    bool shouldBeRunning = knownRoots.isNotEmpty && sdkManager.hasSdk;

    if (dispose || (!shouldBeRunning && _server != null)) {
      // shutdown
      _server.kill();
    } else if (shouldBeRunning) {
      // startup
      if (_server == null) {
        _AnalysisServerWrapper server = _AnalysisServerWrapper.create(sdkManager.sdk);
        _server = server;
        _initNewServer(server);
      } else if (!_server.isRunning) {
        _server.restart(sdkManager.sdk);
        _initExistingServer(_server);
      }
    }
  }

  void _initNewServer(_AnalysisServerWrapper server) {
    server.onAnalyzing.listen((value) => _serverBusyController.add(value));
    server.onDisposed.listen((exitCode) => _handleServerDeath(server));

    server.onSend.listen((message) => _onSendController.add(message));
    server.onReceive.listen((message) => _onReceiveController.add(message));

    server.analysis.onNavigation.listen((e) => _onNavigatonController.add(e));

    onBusy.listen((busy) {
      if (!busy && _job != null) {
        _job.finish();
        _job = null;
      } else if (busy && _job == null) {
        _job = new _AnalyzingJob()..start();
      }
    });

    _initExistingServer(server);
  }

  void _initExistingServer(Server server) {
    _serverActiveController.add(true);
    _syncRoots();
    _focusedEditorChanged(editorManager.dartProjectEditors.activeEditor);
  }

  void _handleServerDeath(Server server) {
    if (_server == server) {
      _serverActiveController.add(false);
      _serverBusyController.add(false);
      errorRepository.clearAll();
    }
  }
}

class _AnalyzingJob extends Job {
  static const Duration _debounceDelay = const Duration(milliseconds: 250);

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

typedef void _AnalysisServerWriter(String);

class _AnalysisServerWrapper extends Server {
  static _AnalysisServerWrapper create(Sdk sdk) {
    StreamController controller = new StreamController();
    ProcessRunner process = _createProcess(sdk);
    Completer completer = _startProcess(process, controller);

    _AnalysisServerWrapper wrapper = new _AnalysisServerWrapper(
        process, completer, controller.stream, _messageWriter(process));
    wrapper.setup();
    return wrapper;
  }

  ProcessRunner process;
  Completer<int> _processCompleter;
  bool analyzing = false;
  StreamController _analyzingController = new StreamController.broadcast();
  StreamController<int> _disposedController = new StreamController.broadcast();

  _AnalysisServerWrapper(this.process, this._processCompleter,
      Stream<String> inStream, void writeMessage(String message)) : super(inStream, writeMessage) {
    _processCompleter.future.then((result) {
      _disposedController.add(result);
      process = null;
    });
  }

  void setup() {
    server.setSubscriptions(['STATUS']);
    // TODO: Remove once 1.12.0 is shipped as stable.
    analysis.updateOptions(new AnalysisOptions(
      enableNullAwareOperators: true
    ));
    server.getVersion().then((v) => _logger.info('version ${v.version}'));
    server.onStatus.listen((ServerStatus status) {
      if (status.analysis != null) {
        analyzing = status.analysis.isAnalyzing;
        _analyzingController.add(analyzing);
      }
    });
  }

  bool get isRunning => process != null;

  Stream<bool> get onAnalyzing => _analyzingController.stream;

  Stream<int> get onDisposed => _disposedController.stream;

  /// Restarts, or starts, the analysis server process.
  void restart(Sdk sdk) {
    var startServer = () {
      var controller = new StreamController();
      process = _createProcess(sdk);
      _processCompleter = _startProcess(process, controller);
      _processCompleter.future.then((result) {
        _disposedController.add(result);
        process = null;
      });
      configure(controller.stream, _messageWriter(process));
      setup();
    };

    if (isRunning) {
      process.kill().then((_) => startServer());
    } else {
      startServer();
    }
  }

  Future<int> kill() {
    _logger.fine("server forcibly terminated");

    if (process != null) {
      try {
        server.shutdown().catchError((e) => null);
      } catch (e) { }

      /*Future f =*/ process.kill();
      process = null;

      try {
        dispose();
      } catch (e) { }

      if (!_processCompleter.isCompleted) _processCompleter.complete(0);

      return new Future.value(0);
    } else {
      _logger.warning("kill signal sent to dead analysis server");
      return new Future.value(1);
    }
  }

  /// Creates a process.
  static ProcessRunner _createProcess(Sdk sdk) {
    List<String> arguments = [
      sdk.getSnapshotPath('analysis_server.dart.snapshot'),
      '--sdk=${sdk.path}'
    ];

    if (AnalysisServer.startWithDebugging) {
      arguments.insert(0, '--observe=${AnalysisServer.OBSERVATORY_PORT}');
      _logger.info('observatory on analysis server available at ${AnalysisServer.observatoryUrl}.');

      arguments.add('--port=${AnalysisServer.DIAGNOSTICS_PORT}');
      _logger.info('analysis server diagnostics available at ${AnalysisServer.diagnosticsUrl}.');
    }

    return new ProcessRunner(sdk.dartVm.path, args: arguments);
  }

  /// Starts a process, and returns a [Completer] that completes when the
  /// process is no longer running.
  static Completer<int> _startProcess(ProcessRunner process, StreamController sc) {
    Completer completer = new Completer();
    process.onStderr.listen((String str) => _logger.severe(str.trim()));

    process.onStdout.listen((String str) {
      List<String> lines = str.trim().split('\n');
      for (String line in lines) {
        sc.add(line.trim());
      }
    });

    process.execStreaming().then((int exitCode) {
      _logger.fine("exited with code ${exitCode}");
      if (!completer.isCompleted) completer.complete(exitCode);
    });

    return completer;
  }

  /// Returns a function that writes to a process stream.
  static _AnalysisServerWriter _messageWriter(ProcessRunner process) {
    return (String message) {
      if (process != null) process.write("${message}\n");
    };
  }
}

class RenameRefactoringOptions extends RefactoringOptions {
  final String newName;

  RenameRefactoringOptions(this.newName);

  Map toMap() => {'newName': newName};
}
