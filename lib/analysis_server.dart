// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Wrapper over the analysis server providing a simplified API and automatic
/// handling of reliability.
library atom.analysis_server;

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:dart_analysis_server_api/protocol.dart';

import 'atom.dart';
import 'process.dart' as process;
import 'projects.dart';
import 'sdk.dart';
import 'state.dart';
import 'utils.dart';


final Logger _logger = new Logger('analysis-server');

// TOOD(lukechurch): Change this to a managed dependency rather than a
// TLV
Sdk _sdk;

// TODO(lukechurch): Dehardcode this
const _SERVER_PATH = '/Users/lukechurch/GitRepos/atom-dartlang-experimental/bin/_analysis_server_entry.dart';

// TODO(lukechurch): Dummy targets, remove these
const _MAIN_PATH = "/Users/lukechurch/scratch-temp/dart_target/main.dart";
const _MAIN_DIR = "/Users/lukechurch/scratch-temp/dart_target";

const _WARMUP_SRC = "void main() { print('a'); }";

const dumpServerMessages = true;

class AnalysisServer implements Disposable {
  StreamSubscriptions subs = new StreamSubscriptions();
  Disposables disposables = new Disposables();
  _Server serverConnection;

  List<DartProject> knownRoots = [];

  AnalysisServer() {
    Timer.run(_setup);
  }

  void _setup() async{
    _logger.fine('setup()');

    subs.add(projectManager.onChanged.listen(_reconcileRoots));
    subs.add(sdkManager.onSdkChange.listen(_handleSdkChange));

    disposables.add(atom.workspace.observeTextEditors(_handleNewEditor));

    _sdk = sdkManager.sdk;

    String sdkPath = _sdk.directory.path;

    // Init server and warmup
    _logger.finer ("SDKPath: $sdkPath");

    serverConnection = new _Server(sdkPath);
    _logger.finer('serverConnection ctor done');

    await serverConnection._setup();

    _logger.finer('_setup() done');

    // Setup watchdog

  }

  // TODO: implement
  /// Returns whether the analysis server is active and running.
  bool get isActive => false;

  /// Provides an instantaneous snapshot of the known issues and warnings.
  List<AnalysisIssue> get issues => null;

  /// Subscribe to this to get told when the issues list has changed.
  Stream get issuesUpdatedNotification => null;

  /// Compute completions for a given location.
  List<Completion> computeCompletions(String sourcePath, int offset) => null;

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

    // TODO: Is this the most efficient way to drive the analysis server?

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

// Server implementation



/**
 * Instances of the class [_Server] manage a connection to a server process, and
 * facilitate communication to and from the server.
 */
class _Server {
  final String _sdkPath;

  /// Control flags to handle the server state machine
  bool isSetup = false;
  bool isSettingUp = false;

  // TODO(lukechurch): Replace this with a notice board + dispatcher pattern
  /// Streams used to handle syncing data with the server
  Stream<bool> analysisComplete;
  StreamController<bool> _onServerStatus;

  Stream<Map> completionResults;
  StreamController<Map> _onCompletionResults;

  _Server(this._sdkPath) {
    _onServerStatus = new StreamController<bool>(sync: true);
    analysisComplete = _onServerStatus.stream.asBroadcastStream();

    _onCompletionResults = new StreamController(sync: true);
    completionResults = _onCompletionResults.stream.asBroadcastStream();
  }

  /// Ensure that the server is ready for use.
  Future _ensureSetup() async {
     _logger.finer("ensureSetup: SETUP $isSetup IS_SETTING_UP $isSettingUp");
    if (!isSetup && !isSettingUp) {
      return _setup();
    }
    return new Future.value();
  }

  Future _setup() async {
     _logger.finer("Setup starting");
    isSettingUp = true;

     _logger.finer("Server about to start");

    await start();
     _logger.finer("Server started");

    listenToOutput(dispatchNotification);
     _logger.finer("listenToOutput returend");
    sendServerSetSubscriptions([ServerService.STATUS]);

     _logger.finer("Server Set Subscriptions completed");

    print ("About to sendAddOverlays");
    await sendAddOverlays({_MAIN_PATH: _WARMUP_SRC});
    print ("sendAddOverlays done");

    print ("About to sendAnalysisSetAnalysisRoots");
    sendAnalysisSetAnalysisRoots([_MAIN_DIR], []);
    print ("sendSetAnalysisRoots done");


    isSettingUp = false;
    isSetup = true;

     _logger.finer("Setup done");
    return analysisComplete.first;
  }

  Future loadSources(Map<String, String> sources) async {
    await sendAddOverlays(sources);
    await sendPrioritySetSources(sources.keys.toList());
  }

  Future unloadSources(List<String> paths) async {
    await sendRemoveOverlays(paths);
  }

  /**
   * Server process object, or null if server hasn't been started yet.
   */
  var _process;

  /**
   * Commands that have been sent to the server but not yet acknowledged, and
   * the [Completer] objects which should be completed when acknowledgement is
   * received.
   */
  final HashMap<String, Completer> _pendingCommands = <String, Completer>{};

  /**
   * Number which should be used to compute the 'id' to send in the next command
   * sent to the server.
   */
  int _nextId = 0;

  /**
   * Stopwatch that we use to generate timing information for debug output.
   */
  Stopwatch _time = new Stopwatch();

  /**
   * Future that completes when the server process exits.
   */
  Future<int> get exitCode => _process.exitCode;

  /**
   * Return a future that will complete when all commands that have been sent
   * to the server so far have been flushed to the OS buffer.
   */
  Future flushCommands() {
    return _process.stdin.flush();
  }

  /**
   * Stop the server.
   */
  Future kill() {
    _logger.severe("Analysis Server forcibly terminated");
    Future<int> exitCode;
    if (_process != null) {
      _process.kill();
      exitCode = _process.exitCode;
      _process = null;
    } else {
      _logger.warning("Kill signal sent to already dead Analysis Server");
      exitCode = new Future.value(1);
    }
    isSetup = false;

    return exitCode;
  }

  /**
   * Start listening to output from the server, and deliver notifications to
   * [notificationProcessor].
   */
  void listenToOutput(NotificationProcessor notificationProcessor) {
    _process.onStdout
        // .transform((new Utf8Codec()).decoder)
        .transform(new LineSplitter())
        .listen((String line) {

          print ("listenToOutput-callback-0");
      String trimmedLine = line.trim();

       _logger.finer('RECV: $trimmedLine');
      var message;
      try {
        message = JSON.decoder.convert(trimmedLine);
      } catch (exception) {
        _logger.severe("Bad data from server");
        return;
      }
      Map messageAsMap = message;
      if (messageAsMap.containsKey('id')) {
        String id = message['id'];
        Completer completer = _pendingCommands[id];
        if (completer == null) {
           _logger.finer('Unexpected response from server: id=$id');
        } else {
          _pendingCommands.remove(id);
        }
        if (messageAsMap.containsKey('error')) {
          // TODO(paulberry): propagate the error info to the completer.
          kill();
          completer.completeError(new UnimplementedError(
              'Server responded with an error: ${JSON.encode(message)}'));
        } else {
          completer.complete(messageAsMap['result']);
        }
        // Check that the message is well-formed.  We do this after calling
        // completer.complete() or completer.completeError() so that we don't
        // stall the test in the event of an error.
        // expect(message, isResponse);
      } else {
        // Message is a notification.  It should have an event and possibly
        // params.
//        expect(messageAsMap, contains('event'));
//        expect(messageAsMap['event'], isString);
        notificationProcessor(messageAsMap['event'], messageAsMap['params']);
        // Check that the message is well-formed.  We do this after calling
        // notificationController.add() so that we don't stall the test in the
        // event of an error.
//        expect(message, isNotification);
      }
    });
    _process.onStderr
        .transform((new Utf8Codec()).decoder)
        .transform(new LineSplitter())
        .listen((String line) {
      _logStdio('ERR:  ${line.trim()}');
    });
  }

  Future get analysisFinished {
    Completer completer = new Completer();
    StreamSubscription subscription;

    // This will only work if the caller has already subscribed to
    // SERVER_STATUS (e.g. using sendServerSetSubscriptions(['STATUS']))
    subscription = analysisComplete.listen((bool p) {
      completer.complete(p);
      subscription.cancel();
    });
    return completer.future;
  }

  /**
   * Send a command to the server.  An 'id' will be automatically assigned.
   * The returned [Future] will be completed when the server acknowledges the
   * command with a response.  If the server acknowledges the command with a
   * normal (non-error) response, the future will be completed with the 'result'
   * field from the response.  If the server acknowledges the command with an
   * error response, the future will be completed with an error.
   */
  Future send(String method, Map<String, dynamic> params) {
     _logger.finer("Server.send $method");

    String id = '${_nextId++}';
    Map<String, dynamic> command = <String, dynamic>{
      'id': id,
      'method': method
    };
    if (params != null) {
      command['params'] = params;
    }
    Completer completer = new Completer();
    _pendingCommands[id] = completer;
    String line = JSON.encode(command);
     _logger.finer('SEND: $line');
    _process.write("${line}\n");
     _logger.finer('SEND-complete');
    // _process.stdin.add(UTF8.encoder.convert("${line}\n"));
    return completer.future;
  }

  /**
   * Start the server.  If [debugServer] is `true`, the server will be started
   * with "--debug", allowing a debugger to be attached. If [profileServer] is
   * `true`, the server will be started with "--observe" and
   * "--pause-isolates-on-exit", allowing the observatory to be used.
   */
  Future start({bool debugServer: false, bool profileServer: false}) async {
    if (_process != null) throw new Exception('Process already started');

    print ("_Server.start");

    print (_sdk);
    print (_sdk.dartVm);
    print (_sdk.dartVm.path);

    print ('paths ok');

    String dartBinary = _sdk.dartVm.path;//   '/usr/local/bin/dart';// io.Platform.executable;
    print ("DartBinary: $dartBinary");
     /*
    String rootDir =
        findRoot(io.Platform.script.toFilePath(windows: io.Platform.isWindows));
    String serverPath = normalize(join(rootDir, 'bin', 'server.dart'));
    String serverPath =
        normalize(join(dirname(io.Platform.script.toFilePath()), 'analysis_server_server.dart'));
 */

    List<String> arguments = [];

    // if (debugServer) {
    //   arguments.add('--debug');
    // }
    // if (profileServer) {
    //   arguments.add('--observe');
    //   arguments.add('--pause-isolates-on-exit');
    // }


    // if (io.Platform.packageRoot.isNotEmpty) {
    //   arguments.add('--package-root=${io.Platform.packageRoot}');
    // }

    arguments.add(_SERVER_PATH);

    arguments.add('--sdk');
    arguments.add(_sdkPath);

    print ("Arguments: $arguments");

     _logger.finer("Binary: $dartBinary");
     _logger.finer("Arguments: $arguments");

    var procRunner = new process.ProcessRunner(dartBinary, args: arguments);

    var exitCode = procRunner.execStreaming();

    while (!procRunner.started) {
      await new Future.delayed(new Duration(seconds: 0));
    }
    _process = procRunner;

    print ("procRunner.started: ${procRunner.started}");
    print ("${_process.onStdout == null}");

    exitCode.then((int code) {
      print ("Analysis Server exitted wtih $code");
      });

    print ("procRunner component started");

    // return io.Process.start(dartBinary, arguments).then((io.Process process) {
    //   print("io.Process.then returned");

      // _process = process;
      // process.exitCode.then((int code) {
      //   _logStdio('TERMINATED WITH EXIT CODE $code');
      // });
    // });
  }

  Future sendServerSetSubscriptions(List<ServerService> subscriptions) {
    var params = new ServerSetSubscriptionsParams(subscriptions).toJson();
    print ("sendServerSetSubscriptions params: $params");
    return send("server.setSubscriptions", params);
  }

  Future sendPrioritySetSources(List<String> paths) {
    var params = new AnalysisSetPriorityFilesParams(paths).toJson();
    return send("analysis.setPriorityFiles", params);
  }

  Future<ServerGetVersionResult> sendServerGetVersion() {
    return send("server.getVersion", null).then((result) {
      ResponseDecoder decoder = new ResponseDecoder(null);
      return new ServerGetVersionResult.fromJson(decoder, 'result', result);
    });
  }

  Future<CompletionGetSuggestionsResult> sendCompletionGetSuggestions(
      String path, int offset) {
    var params = new CompletionGetSuggestionsParams(path, offset).toJson();
    return send("completion.getSuggestions", params).then((result) {
      ResponseDecoder decoder = new ResponseDecoder(null);
      return new CompletionGetSuggestionsResult.fromJson(
          decoder, 'result', result);
    });
  }

  Future<EditGetFixesResult> sendGetFixes(String path, int offset) {
    var params = new EditGetFixesParams(path, offset).toJson();
    return send("edit.getFixes", params).then((result) {
      ResponseDecoder decoder = new ResponseDecoder(null);
      return new EditGetFixesResult.fromJson(decoder, 'result', result);
    });
  }

  Future<EditFormatResult> sendFormat(int selectionOffset,
      [int selectionLength = 0]) {
    var params = new EditFormatParams(
        mainPath, selectionOffset, selectionLength).toJson();

    return send("edit.format", params).then((result) {
      ResponseDecoder decoder = new ResponseDecoder(null);
      return new EditFormatResult.fromJson(decoder, 'result', result);
    });
  }

  Future<AnalysisUpdateContentResult> sendAddOverlays(
      Map<String, String> overlays) {
        print ('sendAddOverlays-00');
    var updateMap = {};
    for (String path in overlays.keys) {
      updateMap.putIfAbsent(path, () => new AddContentOverlay(overlays[path]));
    }
    print ('sendAddOverlays-01');

    var params = new AnalysisUpdateContentParams(updateMap).toJson();
    print ('sendAddOverlays-02');

     _logger.finer("About to send analysis.updateContent");
     _logger.finer("Paths to update: ${updateMap.keys}");
    return send("analysis.updateContent", params).then((result) {
       _logger.finer("analysis.updateContent -> then");

      ResponseDecoder decoder = new ResponseDecoder(null);
      return new AnalysisUpdateContentResult.fromJson(
          decoder, 'result', result);
    });
  }

  Future<AnalysisUpdateContentResult> sendRemoveOverlays(List<String> paths) {
    var updateMap = {};
    var overlay = new RemoveContentOverlay();
    paths.forEach((String path) => updateMap.putIfAbsent(path, () => overlay));

    var params = new AnalysisUpdateContentParams(updateMap).toJson();
     _logger.finer("About to send analysis.updateContent - remove overlay");
     _logger.finer("Paths to remove: ${updateMap.keys}");
    return send("analysis.updateContent", params).then((result) {
       _logger.finer("analysis.updateContent -> then");

      ResponseDecoder decoder = new ResponseDecoder(null);
      return new AnalysisUpdateContentResult.fromJson(
          decoder, 'result', result);
    });
  }

  Future sendServerShutdown() {
    return send("server.shutdown", null).then((result) {
      isSetup = false;
      return null;
    });
  }

  Future sendAnalysisSetAnalysisRoots(
      List<String> included, List<String> excluded,
      {Map<String, String> packageRoots}) {

    var params = new AnalysisSetAnalysisRootsParams(included, excluded,
        packageRoots: packageRoots).toJson();
    return send("analysis.setAnalysisRoots", params);
  }

  Future dispatchNotification(String event, params) async {
    if (event == "server.error") {
      // Something has gone wrong with the analysis server. This request is going
      // to fail, but we need to restart the server to be able to process
      // another request

      await kill();
      _onCompletionResults.addError(null);
      _logger.severe("Analysis server has crashed. $event");
      return;
    }

    if (event == "server.status" &&
        params.containsKey('analysis') &&
        !params['analysis']['isAnalyzing']) {
      _onServerStatus.add(true);
    }

    // Ignore all but the last completion result. This means that we get a
    // precise map of the completion results, rather than a partial list.
    if (event == "completion.results" && params["isLast"]) {
      _onCompletionResults.add(params);
    }
  }

  /**
   * Record a message that was exchanged with the server, and print it out if
   * [dumpServerMessages] is true.
   */
  void _logStdio(String line) {
    if (dumpServerMessages)  _logger.finer(line);
  }
}


// Interface API classes strip these down as needs be

// ==============

class AnalysisResults {
  final List<AnalysisIssue> issues;

  @ApiProperty(description: 'The package imports parsed from the source.')
  final List<String> packageImports;

  @ApiProperty(description: 'The resolved imports - e.g. dart:async, dart:io, ...')
  final List<String> resolvedImports;

  AnalysisResults(this.issues, this.packageImports, this.resolvedImports);
}

class AnalysisIssue implements Comparable {
  final String kind;
  final int line;
  final String message;
  final String sourceName;

  final bool hasFixes;

  final int charStart;
  final int charLength;
  // TODO: Once all clients have started using fullName, we should remove the
  // location field.
  final String location;

  AnalysisIssue.fromIssue(this.kind, this.line, this.message,
      {this.charStart, this.charLength, this.location,
      this.sourceName, this.hasFixes: false});

  Map toMap() {
    Map m = {'kind': kind, 'line': line, 'message': message};
    if (charStart != null) m['charStart'] = charStart;
    if (charLength != null) m['charLength'] = charLength;
    if (hasFixes != null) m['hasFixes'] = hasFixes;
    if (sourceName != null) m['sourceName'] = sourceName;

    return m;
  }

  int compareTo(AnalysisIssue other) => line - other.line;

  String toString() => '${kind}: ${message} [${line}]';
}

class SourceRequest {
  String source;

  int offset;
}

class SourcesRequest {
  Map<String, String> sources;

  Location location;
}

class Location {
  String sourceName;
  int offset;
}

class CompileRequest {
  String source;

  bool useCheckedMode;

  bool returnSourceMap;
}

class CompileResponse {
  final String result;
  final String sourceMap;

  CompileResponse(this.result, [this.sourceMap]);
}

class CounterRequest {
  String name;
}

class CounterResponse {
  final int count;

  CounterResponse(this.count);
}

class DocumentResponse {
  final Map<String, String> info;

  DocumentResponse(this.info);
}

class CompleteResponse {
  final int replacementOffset;

  final int replacementLength;

  final List<Map<String, String>> completions;

  CompleteResponse(
      this.replacementOffset, this.replacementLength, List<Map> completions) :
    this.completions = _convert(completions);

  /**
   * Convert any non-string values from the contained maps.
   */
  static List<Map<String, String>> _convert(List<Map> list) {
    return list.map((m) {
      Map newMap = {};
      for (String key in m.keys) {
        var data = m[key];
        // TODO: Properly support Lists, Maps (this is a hack).
        if (data is Map || data is List) {
          data = JSON.encode(data);
        }
        newMap[key] = '${data}';
      }
      return newMap;
    }).toList();
  }
}

class FixesResponse {
  final List<ProblemAndFixes> fixes;

  FixesResponse(List<AnalysisErrorFixes> analysisErrorFixes) :
    this.fixes = _convert(analysisErrorFixes);

  /**
   * Convert between the Analysis Server type and the API protocol types.
   */
  static List<ProblemAndFixes> _convert(List<AnalysisErrorFixes> list) {
    var problemsAndFixes = new List<ProblemAndFixes>();
    list.forEach((fix) => problemsAndFixes.add(_convertAnalysisErrorFix(fix)));
    return problemsAndFixes;
  }

  static ProblemAndFixes _convertAnalysisErrorFix(AnalysisErrorFixes analysisFixes) {
    String problemMessage = analysisFixes.error.message;
    int problemOffset = analysisFixes.error.location.offset;
    int problemLength = analysisFixes.error.location.length;

    List<CandidateFix> possibleFixes = new List<CandidateFix>();

    for (var sourceChange in analysisFixes.fixes) {
      List<SourceEdit> edits = new List<SourceEdit>();

      // A fix that tries to modify other files is considered invalid.

      bool invalidFix = false;
      for (var sourceFileEdit in sourceChange.edits) {
        // TODO(lukechurch): replace this with a more reliable test based on the
        // psuedo file name in Analysis Server
        if (!sourceFileEdit.file.endsWith("/main.dart")) {
          invalidFix = true;
          break;
        }

        for (var sourceEdit in sourceFileEdit.edits) {
          edits.add(new SourceEdit.fromChanges(
              sourceEdit.offset,
              sourceEdit.length,
              sourceEdit.replacement));
        }
      }
      if (!invalidFix) {
        CandidateFix possibleFix = new
          CandidateFix.fromEdits(sourceChange.message, edits);
        possibleFixes.add(possibleFix);
      }
    }
    return new ProblemAndFixes.fromList(
        possibleFixes,
        problemMessage,
        problemOffset,
        problemLength);
  }
}

/**
 * Represents a problem detected during analysis, and a set of possible
 * ways of resolving the problem.
 */
class ProblemAndFixes {
  //TODO(lukechurch): consider consolidating this with [AnalysisIssue]
  final List<CandidateFix> fixes;
  final String problemMessage;
  final int offset;
  final int length;

  ProblemAndFixes() : this.fromList([]);
  ProblemAndFixes.fromList(
      [this.fixes, this.problemMessage, this.offset, this.length]);
}

/**
 * Represents a possible way of solving an Analysis Problem.
 */
class CandidateFix {
  final String message;
  final List<SourceEdit> edits;

  CandidateFix() : this.fromEdits();
  CandidateFix.fromEdits([this.message, this.edits]);
}

/**
 * Represents a reformatting of the code.
 */
class FormatResponse {
  final String newString;

  final int offset;

  FormatResponse(this.newString, [this.offset = 0]);
}

/**
 * Represents a single edit-point change to a source file.
 */
class SourceEdit {
  final int offset;
  final int length;
  final String replacement;

  SourceEdit() : this.fromChanges();
  SourceEdit.fromChanges([this.offset, this.length, this.replacement]);

  String applyTo(String target) {
    if (offset >= replacement.length) {
      throw "Offset beyond end of string";
    } else if (offset + length >= replacement.length) {
      throw "Change beyond end of string";
    }

    String pre = "${target.substring(0, offset)}";
    String post = "${target.substring(offset+length)}";
    return "$pre$replacement$post";
  }
}

/// The response from the `/version` service call.
class VersionResponse {
  final String sdkVersion;

  final String runtimeVersion;

  final String appEngineVersion;

  final String servicesVersion;

  VersionResponse({this.sdkVersion, this.runtimeVersion,
    this.appEngineVersion, this.servicesVersion});
}

// ====================================
