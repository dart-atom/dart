// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Wrapper over the analysis server providing a simplified API and automatic
/// handling of reliability.
library atom.analysis_server;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:frappe/frappe.dart';
//import 'package:markdown/markdown.dart';

import 'atom.dart';
import 'dependencies.dart';
import 'editors.dart';
import 'jobs.dart';
import 'projects.dart';
import 'process.dart';
import 'sdk.dart';
import 'state.dart';
import 'utils.dart';
import 'impl/analysis_server_dialog.dart';
import 'impl/analysis_server_gen.dart';

final Logger _logger = new Logger('analysis-server');

class AnalysisServer implements Disposable {
  StreamSubscriptions subs = new StreamSubscriptions();
  Disposables disposables = new Disposables();

  StreamController<bool> _serverActiveController = new StreamController.broadcast();
  StreamController<bool> _serverBusyController = new StreamController.broadcast();
  StreamController<String> _onSendController = new StreamController.broadcast();
  StreamController<String> _onReceiveController = new StreamController.broadcast();

  _AnalysisServerWrapper _server;
  _AnalyzingJob _job;

  List<DartProject> knownRoots = [];

  Property<bool> isActiveProperty;

  AnalysisServer() {
    // onActive.listen((val) => _logger.info('analysis server active: ${val}'));
    // onBusy.listen((val) => _logger.info('analysis server busy: ${val}'));
    isActiveProperty = new Property.fromStreamWithInitialValue(false, onActive);
    Timer.run(_setup);
  }

  Stream<bool> get onActive => _serverActiveController.stream;
  Stream<bool> get onBusy => _serverBusyController.stream;

  Stream<String> get onSend => _onSendController.stream;
  Stream<String> get onReceive => _onReceiveController.stream;

  // TODO: is it better to just expose _server?
  Stream<AnalysisErrors> get onAnalysisErrors =>
      analysisServer._server.analysis.onErrors;

  Server get server => _server;

  void _setup() {
    subs.add(projectManager.onChanged.listen(_reconcileRoots));
    subs.add(sdkManager.onSdkChange.listen(_handleSdkChange));

    disposables.add(atom.workspace.observeTextEditors(_handleNewEditor));

    editorManager.onDartFileChanged.listen(_focusedDartFileChanged);

    knownRoots = projectManager.projects.toList();

    _checkTrigger();

    // Create the analysis server diagnostics dialog.
    disposables.add(deps[AnalysisServerDialog] = new AnalysisServerDialog());

    disposables.add(atom.commands.add('atom-text-editor',
        'dart-lang-experimental:show-dartdoc', (event) {
      DartdocHelper.handleDartdoc(_server, event);
    }));

    disposables.add(atom.commands.add('atom-text-editor',
        'dart-lang-experimental:jump-to-declaration', (event) {
      DeclarationHelper.handleNavigate(_server, event);
    }));

    disposables.add(atom.commands.add('atom-text-editor',
        'dart-lang-experimental:quick-fix', (event) {
      QuickFixHelper.handleQuickFix(_server, event);
    }));

    onSend.listen((String message)    => _logger.finer('--> ${message}'));
    onReceive.listen((String message) => _logger.finer('<-- ${message}'));
  }

  /// Returns whether the analysis server is active and running.
  bool get isActive => _server.isRunning;

  bool get isBusy => _server.analyzing;

  /// Subscribe to this to get told when the issues list has changed.
  Stream get issuesUpdatedNotification => null;

  // /// Compute completions for a given location.
  // List<Completion> computeCompletions(String sourcePath, int offset) => null;

  Future<ErrorsResult> getErrors(String filePath) {
    if (isActive) {
      return _server.analysis.getErrors(filePath);
    } else {
      return new Future.value(new ErrorsResult([]));
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
    editor.onDidStopChanging.listen((_) => notifyFileChanged(path, editor.getText()));

    editor.onDidDestroy.listen((_) => notifyFileChanged(path, null));
  }

  void _focusedDartFileChanged(File file) {
    if (file != null && _server != null) {
      // TODO: What a truly interesting API.
      _server.analysis.setSubscriptions({'NAVIGATION': [file.getPath()]});
    }
  }

  /// Explictely and manually start the analysis server. This will not succeed
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
    if (_server != null) _server.analysis.reanalyze();
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
    server.whenDisposed.then((exitCode) => _handleServerDeath(server));

    server.onSend.listen((message) => _onSendController.add(message));
    server.onReceive.listen((message) => _onReceiveController.add(message));

    server.analysis.onNavigation.listen((AnalysisNavigation e) {
      DeclarationHelper.setLastNavInfo(e);
    });

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
    _focusedDartFileChanged(editorManager.activeDartFile);
  }

  void _handleServerDeath(Server server) {
    if (_server == server) {
      _serverActiveController.add(false);
      _serverBusyController.add(false);
    }
  }
}

class DartdocHelper {
  static void handleDartdoc(Server server, AtomEvent event) {
    if (server == null) return;

    bool explicit = true;

    TextEditor editor = event.editor;
    Range range = editor.getSelectedBufferRange();
    int offset = editor.getBuffer().characterIndexForPosition(range.start);
    server.analysis.getHover(editor.getPath(), offset).then((HoverResult result) {
      if (result.hovers.isEmpty) {
        if (explicit) atom.beep();
        return;
      }

      HoverInformation hover = result.hovers.first;
      atom.notifications.addInfo(_title(hover),
          dismissable: true, detail: _render(hover));
    });
  }

  static String _title(HoverInformation hover) {
    if (hover.elementDescription != null) return hover.elementDescription;
    if (hover.staticType != null) return hover.staticType;
    if (hover.propagatedType != null) return hover.propagatedType;
    return 'Dartdoc';
  }

  static String _render(HoverInformation hover) {
    StringBuffer buf = new StringBuffer();
    if (hover.containingLibraryName != null) buf
        .write('library: ${hover.containingLibraryName}\n');
    if (hover.containingClassDescription != null) buf
        .write('class: ${hover.containingClassDescription}\n');
    if (hover.propagatedType != null) buf
        .write('propagated type: ${hover.propagatedType}\n');
    // TODO: Translate markdown.
    if (hover.dartdoc != null) buf.write('\n${_renderMarkdownToText(hover.dartdoc)}\n');
    return buf.toString();
  }

  static String _renderMarkdownToText(String str) {
    if (str == null) return null;

    StringBuffer buf = new StringBuffer();

    List<String> lines = str.replaceAll('\r\n', '\n').split('\n');

    for (String line in lines) {
      if (line.trim().isEmpty) {
        buf.write('\n');
      } else {
        buf.write('${line.trimRight()} ');
      }
    }

    return buf.toString();
  }
}

class DeclarationHelper {
  static AnalysisNavigation _lastNavInfo;

  static void setLastNavInfo(AnalysisNavigation info) {
    _lastNavInfo = info;
  }

  static void handleNavigate(Server server, AtomEvent event) {
    if (server == null) return;

    // TODO: We should wait for a period of time before failing.
    if (_lastNavInfo == null) {
      atom.beep();
      return;
    }

    TextEditor editor = event.editor;
    String path = editor.getPath();

    if (path != _lastNavInfo.file) {
      atom.beep();
      return;
    }

    Range range = editor.getSelectedBufferRange();
    int offset = editor.getBuffer().characterIndexForPosition(range.start);

    List<String> files = _lastNavInfo.files;
    List<NavigationTarget> targets = _lastNavInfo.targets;
    List<NavigationRegion> regions = _lastNavInfo.regions;

    for (NavigationRegion region in regions) {
      if (region.offset <= offset && (region.offset + region.length > offset)) {
        NavigationTarget target = targets[region.targets.first];
        String file = files[target.fileIndex];
        TextBuffer buffer = editor.getBuffer();
        Range sourceRange = new Range.fromPoints(
          buffer.positionForCharacterIndex(region.offset),
          buffer.positionForCharacterIndex(region.offset + region.length));

        EditorManager.flashSelection(editor, sourceRange).then((_) {
          Map options = {
            'initialLine': target.startLine - 1,
            'initialColumn': target.startColumn - 1,
            'searchAllPanes': true
          };
          atom.workspace.open(file, options).then((TextEditor editor) {
            editor.selectRight(target.length);
          }).catchError((e) {
            _logger.warning('${e}');
            atom.beep();
          });
        });

        return;
      }
    }

    atom.beep();
  }
}

class QuickFixHelper {
  static void handleQuickFix(Server server, AtomEvent event) {
    if (server == null) return;

    TextEditor editor = event.editor;
    String path = editor.getPath();
    Range range = editor.getSelectedBufferRange();
    int offset = editor.getBuffer().characterIndexForPosition(range.start);

    server.edit.getFixes(path, offset).then((FixesResult result) {
      List<AnalysisErrorFixes> fixes = result.fixes;

      if (fixes.isEmpty) {
        atom.beep();
        return;
      }

      List<SourceChange> changes = fixes
        .expand((fix) => fix.fixes)
        .where((SourceChange change) =>
            change.edits.every((SourceFileEdit edit) => edit.file == path))
        .toList();

      if (changes.isEmpty) {
        atom.beep();
        return;
      }

      if (changes.length == 1) {
        // Apply the fix.
        _applyChange(editor, changes.first);
      } else {
        // TODO: Show a selection dialog.
        _logger.info('multiple fixes returned (${changes.length})');
        atom.beep();
      }
    }).catchError((e) {
      _logger.warning('${e}');
      atom.beep();
    });
  }

  static void _applyChange(TextEditor editor, SourceChange change) {
    List<SourceFileEdit> sourceFileEdits = change.edits;
    List<LinkedEditGroup> linkedEditGroups = change.linkedEditGroups;

    List<SourceEdit> edits = sourceFileEdits.expand((e) => e.edits).toList();
    EditorManager.applyEdits(editor, edits);
    EditorManager.selectEditGroups(editor, linkedEditGroups);

    atom.notifications.addSuccess(
        'Executed quick fix: ${toStartingLowerCase(change.message)}');
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

  _AnalysisServerWrapper(this.process, this._processCompleter,
      Stream<String> inStream, void writeMessage(String message)) : super(inStream, writeMessage);

  void setup() {
    server.setSubscriptions(['STATUS']);
    server.onStatus.listen((ServerStatus status) {
      if (status.analysis != null) {
        analyzing = status.analysis.isAnalyzing;
        _analyzingController.add(analyzing);
      }
    });
  }

  bool get isRunning => process != null;

  Stream<bool> get onAnalyzing => _analyzingController.stream;

  Future<int> get whenDisposed => _processCompleter.future;

  /// Restarts, or starts, the analysis server process.
  void restart(sdk) {
    var startServer = () {
      var controller = new StreamController();
      process = _createProcess(sdk);
      _processCompleter = _startProcess(process, controller);
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
      /*Future f =*/ process.kill();
      process = null;
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
      '--sdk',
      sdk.path
    ];

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
    return (String message) => process.write("${message}\n");
  }
}
