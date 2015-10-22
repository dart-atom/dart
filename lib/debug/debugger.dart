library atom.debugger;

import 'dart:async';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../launch/launch.dart';
import '../state.dart';
import '../utils.dart';
import 'debugger_ui.dart';

const bool debugDefault = true;

final Logger _logger = new Logger('atom.debugger');

void _displayError(dynamic error) {
  atom.notifications.addError('${error}');
}

// TODO: Track current debug target - fire when it changes.

class DebugManager implements Disposable {
  Disposables disposables = new Disposables();

  List<DebugConnection> connections = [];

  StreamController<DebugConnection> _addedController = new StreamController.broadcast();
  StreamController<DebugConnection> _removedController = new StreamController.broadcast();

  DebugManager() {
    onAdded.listen((DebugConnection connection) {
      DebugUIController controller = new DebugUIController(connection);
      connection.onTerminated.then((_) {
        controller.dispose();
      });
    });

    var add = (String cmd, Function closure) {
      disposables.add(atom.commands.add('atom-workspace', 'dartlang:${cmd}', (_) {
        closure();
      }));
    };
    add('debug-run', _handleDebugRun);
    add('debug-terminate', () => activeConnection?.terminate());
    add('debug-stepout', () => activeConnection?.stepOut());
    add('debug-step', () => activeConnection?.stepOver());
    add('debug-stepin', () => activeConnection?.stepIn());
  }

  Stream<DebugConnection> get onAdded => _addedController.stream;

  Stream<DebugConnection> get onRemoved => _removedController.stream;

  void addConnection(DebugConnection connection) {
    connections.add(connection);
    _addedController.add(connection);
  }

  // TODO: Maintain a notion of an active debug connection.
  DebugConnection get activeConnection =>
      connections.isEmpty ? null : connections.first;

  void removeConnection(DebugConnection connection) {
    connections.remove(connection);
    _removedController.add(connection);
  }

  void _handleDebugRun() {
    DebugConnection connection = activeConnection;

    if (connection != null) {
      connection.resume().catchError(_displayError);
    } else {
      TextEditor editor = atom.workspace.getActiveTextEditor();
      if (editor != null) {
        atom.commands.dispatch(atom.views.getView(editor), 'dartlang:run-application');
      }
    }
  }

  void dispose() {
    disposables.dispose();
    connections.toList().forEach((c) => c.dispose());
  }
}

abstract class DebugConnection {
  final Launch launch;

  DebugConnection(this.launch);

  bool get isAlive;
  bool get isSuspended;

  // TODO: temporary
  DebugIsolate get isolate;

  DebugFrame get topFrame;

  pause();
  Future resume();
  stepIn();
  stepOver();
  stepOut();
  terminate();

  Stream<bool> get onSuspendChanged;

  Future get onTerminated;

  void dispose();
}

/// A representation of a VM Isolate.
abstract class DebugIsolate {
  DebugIsolate();

  String get name;
}

abstract class DebugFrame {
  DebugFrame();

  String get title;

  String get cursorDescription;

  List<DebugVariable> get locals;

  Future<String> eval(String expression);

  String toString() => title;
}

abstract class DebugVariable {
  DebugVariable();

  String get name;
  String get valueDescription;

  String toString() => name;
}

/// A class to translate from one name-space to another.
class UriTranslator {
  /// Convert urls like:
  /// - `http://localhost:9888/packages/flutter/src/material/dialog.dart`
  /// - `http://localhost:9888/lib/main.dart`
  ///
  /// To urls like:
  /// - `package:flutter/src/material/dialog.dart`
  /// - `file:///foo/projects/my_project/lib/main.dart`
  ///
  /// This call does not translate `dart:` urls.
  String targetToClient(String str) => str;

  /// Convert urls from:
  /// - `package:flutter/src/material/dialog.dart`
  /// - `file:///foo/projects/my_project/lib/main.dart`
  ///
  /// To urls like:
  /// - `http://localhost:9888/packages/flutter/src/material/dialog.dart`
  /// - `http://localhost:9888/lib/main.dart`
  ///
  /// This call does not translate `dart:` urls.
  String clientToTarget(String str) => str;
}

class UriResolver implements Disposable {
  final String root;
  final String selfRefName;

  UriTranslator _translator;
  String _selfRefPrefix;

  final Map<String, String> _uriToPath = {};
  final Map<String, List<String>> _pathToUri = {};

  Completer _completer = new Completer();
  String _contextId;

  UriResolver(this.root, {UriTranslator translator, this.selfRefName}) {
    this._translator = translator ?? new UriTranslator();
    if (selfRefName != null) _selfRefPrefix = 'package:${selfRefName}/';

    if (analysisServer.isActive) {
      analysisServer.server.execution.createContext(root).then((var result) {
        _contextId = result.id;
        _completer.complete(_contextId);
      }).catchError((e) {
        _completer.completeError(e);
      });
    } else {
      _completer.completeError('analysis server not available');
    }
  }

  Future<String> resolveUriToPath(String uri) {
    return _resolveUriToPath(uri).then((result) {
      _logger.finer('resolve ${uri} <== ${result}');
      return result;
    });
  }

  Future<String> _resolveUriToPath(String uri) {
    uri = _translator.targetToClient(uri);

    if (uri.startsWith('file:///')) return new Future.value(uri.substring(7));
    if (uri.startsWith('file:/')) return new Future.value(uri.substring(5));

    if (_uriToPath.containsKey(uri)) return new Future.value(_uriToPath[uri]);

    return _completer.future.then((String contextId) {
      return analysisServer.server.execution.mapUri(contextId, uri: uri);
    }).then((result) {
      String path = result.file;
      _uriToPath[uri] = path;
      return path;
    });
  }

  /// This can return one or two results.
  Future<List<String>> resolvePathToUri(String path) {
    return _resolvePathToUri(path).then((result) {
      _logger.finer('resolve ${path} ==> ${result}');
      return result;
    });
  }

  Future<String> _resolvePathToUri(String path) {
    // if (uri.startsWith('file:///')) return new Future.value(uri.substring(7));
    // if (uri.startsWith('file:/')) return new Future.value(uri.substring(5));
    if (_pathToUri.containsKey(path)) return new Future.value(_pathToUri[path]);

    return _completer.future.then((String contextId) {
      return analysisServer.server.execution.mapUri(contextId, file: path);
    }).then((result) {
      List<String> uris = [result.uri];

      if (result.uri.startsWith(_selfRefPrefix)) {
        String filePath = root.startsWith('/') ? 'file://${root}' : 'file:///${root}';
        filePath += '/lib/${result.uri.substring(_selfRefPrefix.length)}';
        uris.insert(0, filePath);
      }

      for (int i = 0; i < uris.length; i++) {
        uris[i] = _translator.clientToTarget(uris[i]);
      }

      _pathToUri[path] = uris;
      return uris;
    });
  }

  void dispose() {
    if (analysisServer.isActive) {
      analysisServer.server.execution.deleteContext(_contextId).catchError((_) {
        return null;
      });
    }
  }

  String toString() => '[UriResolver for ${root}]';
}
