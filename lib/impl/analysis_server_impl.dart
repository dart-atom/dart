// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.analysis_server_impl;

import 'dart:async';
import 'dart:convert';

import 'package:dart_analysis_server_api/protocol.dart';
import 'package:logging/logging.dart';

import '../process.dart';
import '../sdk.dart';

final Logger _logger = new Logger('analysis-server-impl');

const _dumpServerMessages = true;

/**
 * Instances of the class [Server] manage a connection to a server process, and
 * facilitate communication to and from the server.
 */
class Server {
  final Sdk sdk;

  /// Control flags to handle the server state machine
  bool isSetup = false;
  bool isSettingUp = false;

  bool _isBusy = false;

  // TODO(lukechurch): Replace this with a notice board + dispatcher pattern
  /// Streams used to handle syncing data with the server
  Stream<bool> analysisComplete;
  StreamController<bool> _onServerStatus;
  StreamController<bool> _busyController = new StreamController.broadcast();
  StreamController<Map> _allMessagesController = new StreamController.broadcast();

  Stream<Map> completionResults;
  StreamController<Map> _onCompletionResults;

  /**
   * Server process object, or null if server hasn't been started yet.
   */
  ProcessRunner _process;

  Completer<int> _processCompleter = new Completer();

  /**
   * Commands that have been sent to the server but not yet acknowledged, and
   * the [Completer] objects which should be completed when acknowledgement is
   * received.
   */
  final Map<String, Completer> _pendingCommands = {};

  /**
   * Number which should be used to compute the 'id' to send in the next command
   * sent to the server.
   */
  int _nextId = 0;

  Server(this.sdk) {
    _onServerStatus = new StreamController<bool>(sync: true);
    analysisComplete = _onServerStatus.stream.asBroadcastStream();

    _onCompletionResults = new StreamController(sync: true);
    completionResults = _onCompletionResults.stream.asBroadcastStream();
  }

  /**
   * Future that completes when the server process exits.
   */
  Future<int> get whenDisposed => _processCompleter.future;

  Stream<bool> get onBusy => _busyController.stream;

  Stream<Map> get onAllMessages => _allMessagesController.stream;

  bool get isBusy => _isBusy;

  // /// Ensure that the server is ready for use.
  // Future _ensureSetup() async {
  //    _logger.fine("ensureSetup: SETUP $isSetup IS_SETTING_UP $isSettingUp");
  //   if (!isSetup && !isSettingUp) {
  //     return setup();
  //   }
  //   return new Future.value();
  // }

  Future setup() async {
    _logger.fine("Setup starting");
    isSettingUp = true;

    _logger.fine("Server about to start");

    await start();

    _logger.fine("Server started");

    listenToOutput();

    _logger.fine("listenToOutput returned");

    sendServerSetSubscriptions([ServerService.STATUS]);

    _logger.fine("set subscriptions completed");

    isSettingUp = false;
    isSetup = true;

    _logger.fine("Setup done");
  }

  Future loadSources(Map<String, String> sources) async {
    await sendAddOverlays(sources);
    await sendPrioritySetSources(sources.keys.toList());
  }

  Future unloadSources(List<String> paths) async {
    await sendRemoveOverlays(paths);
  }

  /// Stop the server.
  Future<int> kill() {
    _logger.fine("server forcibly terminated");

    isSetup = false;

    if (_process != null) {
      /*Future f =*/ _process.kill();
      _process = null;
      if (!_processCompleter.isCompleted) _processCompleter.complete(0);
      return new Future.value(0);
    } else {
      _logger.warning("kill signal sent to dead analysis server");
      return new Future.value(1);
    }
  }

  /**
   * Start listening to output from the server, and deliver notifications to
   * [notificationProcessor].
   */
  void listenToOutput() {
    _process.onStdout.listen((String str) {
      List<String> lines = str.trim().split('\n');

      for (String line in lines) {
        line = line.trim();

        _logger.finer('<-- ${line}');

        Map message;

        try {
          message = JSON.decoder.convert(line);
        } catch (exception) {
          _logger.severe("Bad data from server");
          continue;
        }

        _processMessage(message);
      }
    });

    _process.onStderr.listen((String str) {
      _logStdio('ERR: ${str.trim()}');
    });
  }

  Future<AnalysisErrorsResult> analysis_getErrors(String filePath) {
    return send('analysis.getErrors', {'file': filePath}).then((Map result) {
      return new AnalysisErrorsResult.from(result);
    });
  }

  void _processMessage(Map message) {
    if (message.containsKey('id')) {
      String id = message['id'];
      Completer completer = _pendingCommands.remove(id);

      if (completer == null) {
        _logger.severe('Unexpected response from server: id=$id');
        return;
      }

      if (message.containsKey('error')) {
        completer.completeError(new RequestError.from(message['error']));
      } else {
        completer.complete(message['result']);
      }
    } else {
      _allMessagesController.add(message);
      dispatchNotification(message['event'], message['params']);
    }
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
   * Send a command to the server. An 'id' will be automatically assigned.
   * The returned [Future] will be completed when the server acknowledges the
   * command with a response. If the server acknowledges the command with a
   * normal (non-error) response, the future will be completed with the 'result'
   * field from the response. If the server acknowledges the command with an
   * error response, the future will be completed with an error.
   */
  Future send(String method, Map<String, dynamic> params) {
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
    _logger.finer('--> $line');
    _process.write("${line}\n");

    return completer.future;
  }

  /**
   * Start the server.
   */
  Future start() {
    if (_process != null) throw new Exception('Process already started');

    List<String> arguments = [
      sdk.getSnapshotPath('analysis_server.dart.snapshot'),
      '--sdk',
      sdk.path
    ];

    _process = new ProcessRunner(sdk.dartVm.path, args: arguments);

    _process.execStreaming().then((int exitCode) {
      _logger.fine("exited with code ${exitCode}");
      if (!_processCompleter.isCompleted) _processCompleter.complete(exitCode);
    });

    return new Future.value();
  }

  Future sendServerSetSubscriptions(List<ServerService> subscriptions) {
    var params = new ServerSetSubscriptionsParams(subscriptions).toJson();
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

  // Future<EditFormatResult> sendFormat(int selectionOffset,
  //     [int selectionLength = 0]) {
  //   var params = new EditFormatParams(
  //       mainPath, selectionOffset, selectionLength).toJson();
  //
  //   return send("edit.format", params).then((result) {
  //     ResponseDecoder decoder = new ResponseDecoder(null);
  //     return new EditFormatResult.fromJson(decoder, 'result', result);
  //   });
  // }

  Future<AnalysisUpdateContentResult> sendAddOverlays(
      Map<String, String> overlays) {
    print('sendAddOverlays-00');
    var updateMap = {};
    for (String path in overlays.keys) {
      updateMap.putIfAbsent(path, () => new AddContentOverlay(overlays[path]));
    }
    print('sendAddOverlays-01');

    var params = new AnalysisUpdateContentParams(updateMap).toJson();
    print('sendAddOverlays-02');

    _logger.fine("About to send analysis.updateContent");
    _logger.fine("Paths to update: ${updateMap.keys}");
    return send("analysis.updateContent", params).then((result) {
      _logger.fine("analysis.updateContent -> then");

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
    _logger.fine("About to send analysis.updateContent - remove overlay");
    _logger.fine("Paths to remove: ${updateMap.keys}");
    return send("analysis.updateContent", params).then((result) {
      _logger.fine("analysis.updateContent -> then");

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

  void dispatchNotification(String event, params) {
    if (event == "server.error") {
      // Something has gone wrong with the analysis server. This request is
      // going to fail, but we need to restart the server to be able to process
      // another request.
      kill().then((_) {
        _onCompletionResults.addError(null);
        _logger.severe("Analysis server has crashed. $event");
      });
    }

    if (event == "server.status" &&
        params.containsKey('analysis') &&
        !params['analysis']['isAnalyzing']) {
      _onServerStatus.add(true);
    }

    if (event == "server.status" && params.containsKey('analysis')) {
      _isBusy = params['analysis']['isAnalyzing'];
      _busyController.add(_isBusy);
    }

    // Ignore all but the last completion result. This means that we get a
    // precise map of the completion results, rather than a partial list.
    if (event == "completion.results" && params["isLast"]) {
      _onCompletionResults.add(params);
    }
  }

  /**
   * Record a message that was exchanged with the server, and print it out if
   * [_dumpServerMessages] is true.
   */
  void _logStdio(String line) {
    if (_dumpServerMessages) _logger.fine(line);
  }
}

// Interface API classes strip these down as needs be

// ==============

class AnalysisResults {
  final List<AnalysisIssue> issues;
  final List<String> packageImports;
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

  AnalysisIssue.fromIssue(this.kind, this.line, this.message, {this.charStart,
      this.charLength, this.location, this.sourceName, this.hasFixes: false});

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
      this.replacementOffset, this.replacementLength, List<Map> completions)
      : this.completions = _convert(completions);

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

  FixesResponse(List<AnalysisErrorFixes> analysisErrorFixes)
      : this.fixes = _convert(analysisErrorFixes);

  /**
   * Convert between the Analysis Server type and the API protocol types.
   */
  static List<ProblemAndFixes> _convert(List<AnalysisErrorFixes> list) {
    var problemsAndFixes = new List<ProblemAndFixes>();
    list.forEach((fix) => problemsAndFixes.add(_convertAnalysisErrorFix(fix)));
    return problemsAndFixes;
  }

  static ProblemAndFixes _convertAnalysisErrorFix(
      AnalysisErrorFixes analysisFixes) {
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
              sourceEdit.offset, sourceEdit.length, sourceEdit.replacement));
        }
      }
      if (!invalidFix) {
        CandidateFix possibleFix =
            new CandidateFix.fromEdits(sourceChange.message, edits);
        possibleFixes.add(possibleFix);
      }
    }
    return new ProblemAndFixes.fromList(
        possibleFixes, problemMessage, problemOffset, problemLength);
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

/// An indication of a problem with the execution of the server, typically in
/// response to a request.
class RequestError {
  /// A code that uniquely identifies the error that occurred.
  final String code;

  /// A short description of the error.
  final String message;

  /// (optional) The stack trace associated with processing the request, used
  /// for debugging the server.
  final String stackTrace;

  RequestError.from(Map m) :
      code = m['code'], message = m['message'], stackTrace = m['stackTrace'];

  String toString() => '${code}: ${message}';
}

class AnalysisErrorsResult {
  final List<AnalysisError> errors;

  AnalysisErrorsResult.empty() : errors = [];

  AnalysisErrorsResult.from(Map m) :
      errors = m['errors'].map((obj) => new AnalysisError.from(obj)).toList()..sort();

  String toString() => '${errors}';
}

class AnalysisError implements Comparable {
  static int _sev(String sev) {
    if (sev == 'ERROR') return 3;
    if (sev == 'WARNING') return 2;
    if (sev == 'INFO') return 1;
    return 0;
  }

  final String severity;
  final String type;
  final String message;
  final String correction;
  final Location location;

  AnalysisError.from(Map m) :
      severity = m['severity'],
      type = m['type'],
      message = m['message'],
      correction = m['correction'],
      location = new Location.from(m['location']);

  int compareTo(other) {
    if (other is! AnalysisError) return 0;
    if (severity != other.severity) return _sev(severity) - _sev(other.severity);
    return location.compareTo(other.location);
  }

  String toString() => message;
}

class Location implements Comparable {
  /// The file containing the range.
  final String file;

  /// The offset of the range.
  final int offset;

  /// The length of the range.
  final int length;

  /// The one-based index of the line containing the first character of the
  /// range.
  final int startLine;

  /// The one-based index of the column containing the first character of the
  /// range.
  final int startColumn;

  Location(Map m) :
      file = m['file'], offset = m['offset'], length = m['length'],
      startLine = m['startLine'], startColumn = m['startColumn'];

  factory Location.from(Map m) {
    if (m == null) return null;
    return new Location(m);
  }

  int compareTo(other) {
    if (other is! Location) return 0;
    if (file != other.file) return file.compareTo(other.file);
    return offset - other.offset;
  }

  String toString() => '${file},${startLine},${startColumn}';
}
