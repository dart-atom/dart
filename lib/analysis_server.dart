// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Wrapper over the analysis server providing a simplified API and automatic
/// handling of reliability.
library atom.analysis_server;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/package.dart';
import 'package:atom/node/process.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';
import 'package:logging/logging.dart';

import 'analysis/analysis_server_lib.dart';
import 'dartino/dartino.dart' show dartino;
import 'jobs.dart';
import 'plugin.dart' show pluginVersion;
import 'projects.dart';
import 'sdk.dart';
import 'state.dart';

export 'analysis/analysis_server_lib.dart' show FormatResult, HoverInformation,
    HoverResult, RequestError, AvailableRefactoringsResult, RefactoringResult,
    RefactoringOptions, SourceEdit, SourceFileEdit, AnalysisOutline, Outline,
    AddContentOverlay, ChangeContentOverlay, RemoveContentOverlay,
    AnalysisErrors, AnalysisFlushResults;
export 'jobs.dart' show Job;

final Logger _logger = new Logger('analysis-server');

class AnalysisServer implements Disposable {
  static bool get startWithDiagnostics =>
      atom.config.getBoolValue('${pluginId}.debugAnalysisServer');
  static bool get useChecked =>
      atom.config.getBoolValue('${pluginId}.analysisServerUseChecked');

  static final int DIAGNOSTICS_PORT = 23072;

  static String get diagnosticsUrl => 'http://localhost:${DIAGNOSTICS_PORT}';

  StreamSubscriptions subs = new StreamSubscriptions();
  Disposables disposables = new Disposables();

  StreamController<bool> _serverActiveController = new StreamController.broadcast();
  StreamController<bool> _serverBusyController = new StreamController.broadcast();
  StreamController<String> _onSendController = new StreamController.broadcast();
  StreamController<String> _onReceiveController = new StreamController.broadcast();
  StreamController<AnalysisNavigation> _onNavigatonController =
      new StreamController.broadcast();
  StreamController<AnalysisOutline> _onOutlineController = new StreamController.broadcast();

  _AnalysisServerWrapper _server;
  _AnalyzingJob _job;

  MethodSend _willSend;

  List<DartProject> knownRoots = [];

  AnalysisServer() {
    Timer.run(_setup);

    bool firstNotification = true;

    onActive.listen((value) {
      if (firstNotification) {
        firstNotification = false;
        return;
      }

      if (value) {
        atom.notifications.addInfo('Dart analysis server starting up.');
      } else {
        if (projectManager.projects.isEmpty) {
          atom.notifications.addInfo(
              'Dart analysis server shutting down (no Dart projects open).');
        } else {
          atom.notifications.addInfo('Dart analysis server shutting down.');
        }
      }
    });
  }

  Stream<bool> get onActive => _serverActiveController.stream;
  Stream<bool> get onBusy => _serverBusyController.stream;

  Stream<String> get onSend => _onSendController.stream;
  Stream<String> get onReceive => _onReceiveController.stream;

  Stream<AnalysisNavigation> get onNavigaton => _onNavigatonController.stream;
  Stream<AnalysisOutline> get onOutline => _onOutlineController.stream;

  Stream<AnalysisErrors> get onAnalysisErrors =>
      analysisServer._server.analysis.onErrors;
  Stream<AnalysisFlushResults> get onAnalysisFlushResults =>
      analysisServer._server.analysis.onFlushResults;

  Server get server => _server;

  set willSend(void fn(String methodName)) {
    _willSend = fn;
    if (_server != null) {
      _server.willSend = _willSend;
    }
  }

  void _setup() {
    subs.add(projectManager.onProjectsChanged.listen(_reconcileRoots));
    subs.add(sdkManager.onSdkChange.listen(_handleSdkChange));

    editorManager.dartProjectEditors.onActiveEditorChanged.listen(_focusedEditorChanged);

    knownRoots.clear();
    knownRoots.addAll(projectManager.projects);

    _checkTrigger();

    var trim = (String str) => str.length > 260 ? str.substring(0, 260) + '…' : str;

    onSend.listen((String message) {
      if (_logger.isLoggable(Level.FINER)) {
        _logger.finer('--> ${trim(message)}');
      }
    });

    onReceive.listen((String message) {
      if (message.startsWith('Observatory listening')) {
        message = message.trim();
        if (AnalysisServer.startWithDiagnostics) {
          message += '\nAnalysis server diagnostics on ${AnalysisServer.diagnosticsUrl}';
        }
        atom.notifications.addInfo('Analysis server', detail: message, dismissable: true);
      }

      if (message.startsWith('Observatory no longer listening')) {
        atom.notifications.addInfo('Analysis server', detail: message.trim(), dismissable: true);
      }

      if (_logger.isLoggable(Level.FINER)) {
        _logger.finer('<-- ${trim(message)}');
      }
    });
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

  void updateRoots() {
    if (isActive) {
      List<String> roots = new List.from(knownRoots.map((dir) => dir.path));
      var pkgRoots = <String, String>{};
      for (String root in roots) {
        if (dartino.isProject(root)) {
          String pkgRoot = dartino.sdkFor(root, quiet: true)?.packageRoot(root);
          if (pkgRoot != null) pkgRoots[root] = pkgRoot;
        }
      }
      _logger.fine("setAnalysisRoots(${roots}, packageRoots: $pkgRoots)");
      _server.analysis.setAnalysisRoots(roots, [], packageRoots: pkgRoots);
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
      updateRoots();
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
      _server.analysis.setSubscriptions({
        'NAVIGATION': [path],
        'OUTLINE': [path]
      });

      server.analysis.setPriorityFiles([path]).catchError((e) {
        if (e is RequestError && e.code == 'UNANALYZED_PRIORITY_FILES') {
          AnalysisOutline outline = new AnalysisOutline(path, null, null);
          _onOutlineController.add(outline);
        } else {
          _logger.warning('Error from setPriorityFiles()', e);
        }
      });
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

  Stream<SearchResult> _searchResultsStream(String id) {
    StreamSubscription sub;
    StreamController<SearchResult> controller = new StreamController(
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

  Future<List<SearchResult>> getSearchResults(String searchId) {
    return _searchResultsStream(searchId).toList();
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

  Future<NavigationResult> getNavigation(String path, int offset, int length) {
    return server.analysis.getNavigation(path, offset, length);
  }

  Future<FixesResult> getFixes(String path, int offset) {
    return server.edit.getFixes(path, offset);
  }

  Future<AssistsResult> getAssists(String path, int offset, int length) {
    return server.edit.getAssists(path, offset, length);
  }

  Future<HoverResult> getHover(String file, int offset) {
    return server.analysis.getHover(file, offset);
  }

  Future<FindElementReferencesResult> findElementReferences(
      String path, int offset, bool includePotential) {
    return server.search.findElementReferences(path, offset, includePotential);
  }

  Future<TypeHierarchyResult> getTypeHierarchy(String path, int offset) =>
      server.search.getTypeHierarchy(path, offset);

  /// Update the given file with a new overlay. [contentOverlay] can be one of
  /// [AddContentOverlay], [ChangeContentOverlay], or [RemoveContentOverlay].
  Future updateContent(String path, Jsonable contentOverlay) {
    return server.analysis.updateContent({path: contentOverlay});
  }

  /// If an analysis server is running, terminate it.
  void shutdown() {
    if (_server != null) _server.kill();
  }

  void _checkTrigger({bool dispose: false}) {
    bool shouldBeRunning = knownRoots.isNotEmpty && sdkManager.hasSdk;

    if (dispose || (!shouldBeRunning && _server != null)) {
      // shutdown
      if (_server != null) _server.kill();
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
    server.analysis.onOutline.listen((e) => _onOutlineController.add(e));

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
    server.willSend = _willSend;
    _serverActiveController.add(true);
    updateRoots();
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
  static const Duration _debounceDelay = const Duration(milliseconds: 400);

  Completer completer = new Completer();
  VoidHandler _infoAction;

  _AnalyzingJob() : super('Analyzing source') {
    _infoAction = () {
      statusViewManager.showSection('analysis-server');
    };
  }

  bool get quiet => true;

  VoidHandler get infoAction => _infoAction;

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

typedef void _AnalysisServerWriter(String message);

class _AnalysisServerWrapper extends Server {
  static _AnalysisServerWrapper create(Sdk sdk) {
    StreamController<String> controller = new StreamController();
    ProcessRunner process = _createProcess(sdk);
    Completer<int> completer = _startProcess(process, controller);

    _AnalysisServerWrapper wrapper = new _AnalysisServerWrapper(
        process, completer, controller.stream, _messageWriter(process));
    wrapper.setup();
    return wrapper;
  }

  ProcessRunner process;
  Completer<int> _processCompleter;
  bool analyzing = false;
  StreamController<bool> _analyzingController = new StreamController.broadcast();
  StreamController<int> _disposedController = new StreamController.broadcast();

  _AnalysisServerWrapper(this.process, this._processCompleter,
      Stream<String> inStream, void writeMessage(String message)) :
        super(inStream, writeMessage) {
    _processCompleter.future.then((result) {
      _disposedController.add(result);
      process = null;
    });
  }

  void setup() {
    server.setSubscriptions(['STATUS']);

    // Tracking `enableSuperMixins` here: github.com/dart-lang/sdk/issues/23772.
    analysis.updateOptions(new AnalysisOptions(
      enableSuperMixins: true
    ));

    server.getVersion().then((v) => _logger.info('version ${v.version}'));
    server.onStatus.listen((ServerStatus status) {
      if (status.analysis != null) {
        analyzing = status.analysis.isAnalyzing;
        _analyzingController.add(analyzing);
      }
    });

    server.onError.listen((ServerError error) {
      StackTrace st = error.stackTrace == null
        ? null
        : new StackTrace.fromString(error.stackTrace);

      _logger.info(error.message, null, st);

      List<NotificationButton> buttons = [
        new NotificationButton('Report Error', () => _reportError(error))
      ];

      if (error.isFatal) {
        atom.notifications.addError(
          'Error from the analysis server: ${error.message}',
          detail: error.stackTrace,
          dismissable: true,
          buttons: buttons
        );
      } else {
        atom.notifications.addWarning(
          'Error from the analysis server: ${error.message}',
          detail: error.stackTrace,
          dismissable: true,
          buttons: buttons
        );
      }
    });
  }

  Future _reportError(ServerError error) async {
    String sdkVersion = await sdkManager.sdk.getVersion();
    String pluginVersion = await atomPackage.getPackageVersion();

    String text = '''
Please report the following to https://github.com/dart-lang/sdk/issues/new:

Exception from analysis server (running from Atom)

### what happened

<please describe what you were doing when this exception occurred>

### version information

- Dart SDK ${sdkVersion}
- Atom ${atom.getVersion()}
- ${pluginId} ${pluginVersion}

### the exception

${error.message} ${error.isFatal ? ' (fatal)' : ''}

```
${error.stackTrace}
```
''';

    String filePath = fs.join(fs.tmpdir, 'bug.md');
    fs.writeFileSync(filePath, text);
    atom.workspace.openPending(filePath);
  }

  bool get isRunning => process != null;

  Stream<bool> get onAnalyzing => _analyzingController.stream;

  Stream<int> get onDisposed => _disposedController.stream;

  /// Restarts, or starts, the analysis server process.
  void restart(Sdk sdk) {
    var startServer = () {
      StreamController<String> controller = new StreamController();
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
      _logger.info("kill signal sent to dead analysis server");
      return new Future.value(1);
    }
  }

  /// Creates a process.
  static ProcessRunner _createProcess(Sdk sdk) {
    List<String> arguments = <String>[];

    // Start in checked mode?
    if (AnalysisServer.useChecked) {
      arguments.add('--checked');
    }

    if (AnalysisServer.startWithDiagnostics) {
      arguments.add('--enable-vm-service=0');
    }

    String path = sdk.getSnapshotPath('analysis_server.dart.snapshot');

    // Run from source if local config points to analysis_server/bin/server.dart.
    final String pathPref = '${pluginId}.analysisServerPath';
    String serverPath = atom.config.getValue(pathPref);
    if (serverPath is String) {
      atom.notifications.addSuccess(
        'Running analysis server from source',
        detail: serverPath
      );
      path = serverPath;
    } else if (serverPath != null) {
      atom.notifications.addError('$pathPref is defined but not a String');
    }

    arguments.add(path);

    // Specify the path to the SDK.
    arguments.add('--sdk=${sdk.path}');

    // Check to see if we should start with diagnostics enabled.
    if (AnalysisServer.startWithDiagnostics) {
      arguments.add('--port=${AnalysisServer.DIAGNOSTICS_PORT}');
      _logger.info('analysis server diagnostics available at '
          '${AnalysisServer.diagnosticsUrl}.');
    }

    arguments.add('--client-id=atom-dartlang');
    arguments.add('--client-version=${pluginVersion}');

    // Allow arbitrary CLI options to the analysis server.
    final String optionsPrefPath = '${pluginId}.analysisServerOptions';
    if (atom.config.getValue(optionsPrefPath) != null) {
      dynamic options = atom.config.getValue(optionsPrefPath);
      if (options is List) {
        arguments.addAll(new List.from(options));
      } else if (options is String) {
        arguments.addAll(options.split('\n'));
      }
    }

    return new ProcessRunner(sdk.dartVm.path, args: arguments);
  }

  /// Starts a process, and returns a [Completer] that completes when the
  /// process is no longer running.
  static Completer<int> _startProcess(ProcessRunner process, StreamController sc) {
    Completer<int> completer = new Completer();
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

// TODO: We need more visible progress for this job - it should put up a toast
// after a ~400ms delay.

typedef Future PerformRequest();

/// A [Job] implementation to wrap calls to the analysis server. It will not run
/// if the analysis server is not active. If the call results in an error from
/// the analysis server, the error will be displayed in a toast and will not be
/// passed back from the returned Future.
class AnalysisRequestJob extends Job {
  final PerformRequest _fn;

  AnalysisRequestJob(String name, this._fn) : super(toTitleCase(name));

  bool get quiet => true;

  Future run() {
    if (!analysisServer.isActive) {
      atom.beep();
      return new Future.value();
    }

    return _fn().catchError((e) {
      if (!analysisServer.isActive) return null;

      if (e is RequestError) {
        atom.notifications.addError('${name} error', detail: '${e.message} (${e.code})');

        if (e.stackTrace == null) {
          _logger.warning('${name} error', e);
        } else {
          _logger.warning('${name} error', e, new StackTrace.fromString(e.stackTrace));
        }

        return null;
      } else {
        throw e;
      }
    });
  }
}
