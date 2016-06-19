library atom.debugger;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/process.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../analysis/analysis_server_lib.dart' show MapUriResult;
import '../state.dart';
import 'debugger_ui.dart';
import 'model.dart';

export 'model.dart' show DebugConnection;

final Logger _logger = new Logger('atom.debugger');

void _displayError(dynamic error) {
  atom.notifications.addError('${error}');
}

// TODO: Track current debug target - fire when it changes.
// Use SelectionGroup.

class DebugManager implements Disposable {
  Disposables disposables = new Disposables();

  List<DebugConnection> connections = [];

  StreamController<DebugConnection> _addedController
      = new StreamController.broadcast();
  StreamController<DebugConnection> _removedController
      = new StreamController.broadcast();

  DebugManager() {
    onAdded.listen((DebugConnection connection) {
      DebuggerView.showViewForConnection(connection);
    });

    var add = (String cmd, Function closure) {
      disposables.add(atom.commands.add('atom-workspace', 'dartlang:${cmd}', (_) {
        closure();
      }));
    };
    add('debug-run', _handleDebugRun);
    add('debug-terminate', () => activeConnection?.terminate());
    add('debug-stepin', () => activeConnection?.stepIn());
    add('debug-step', () => activeConnection?.stepOver());
    add('debug-stepout', () => activeConnection?.stepOut());
  }

  DebuggerView showViewForConnection(DebugConnection connection) {
    return DebuggerView.showViewForConnection(connection);
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

  Completer<String> _completer = new Completer<String>();
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
    return _resolveUriToPath(uri).then((String result) {
      _logger.finer('resolve ${uri} <== ${result}');
      return result;
    });
  }

  Future<String> _resolveUriToPath(String uri) async {
    uri = _translator.targetToClient(uri);

    if (uri.startsWith('file:')) return _fileUriToPath(uri);
    if (_uriToPath.containsKey(uri)) return _uriToPath[uri];

    String contextId = await _completer.future;
    MapUriResult result = await analysisServer.server.execution.mapUri(contextId, uri: uri);
    String path = result.file;
    _uriToPath[uri] = path;
    return path;
  }

  /// This can return one or two results.
  Future<List<String>> resolvePathToUris(String path) {
    return _resolvePathToUris(path).then((List<String> results) {
      _logger.finer('resolve ${path} ==> ${results}');
      return results;
    });
  }

  Future<List<String>> _resolvePathToUris(String path) async {
    if (_pathToUri.containsKey(path)) return _pathToUri[path];

    String contextId = await _completer.future;
    MapUriResult result = await analysisServer.server.execution.mapUri(contextId, file: path);
    if (result.uri == null) return [];

    List<String> uris = [result.uri];

    if (_selfRefPrefix != null && result.uri.startsWith(_selfRefPrefix)) {
      String filePath = new Uri.file(root, windows: isWindows).toString();
      filePath += '/lib/${result.uri.substring(_selfRefPrefix.length)}';
      uris.insert(0, filePath);
    }

    for (int i = 0; i < uris.length; i++) {
      uris[i] = _translator.clientToTarget(uris[i]);
    }

    _pathToUri[path] = uris;
    return uris;
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

const List<String> _fileUriPrefixes = const ['file:///', 'file:/'];

String _fileUriToPath(String uriStr) {
  try {
    Uri uri = Uri.parse(uriStr);
    return uri.toFilePath(windows: isWindows);
  } catch (_) {
    for (String prefix in _fileUriPrefixes) {
      if (uriStr.startsWith(prefix)) {
        return isWindows
          ? uriStr.substring(prefix.length)
          : uriStr.substring(prefix.length - 1);
      }
    }

    return uriStr.substring(5);
  }
}
