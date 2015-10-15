library atom.debug;

import 'dart:async';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../launch.dart';
import '../utils.dart';
import 'debug_ui.dart';

final Logger _logger = new Logger('atom.debug');

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

  void dispose() => disposables.dispose();
}

abstract class DebugConnection {
  final Launch launch;

  DebugConnection(this.launch);

  pause();
  Future resume();
  stepIn();
  stepOver();
  stepOut();
  terminate();

  Future get onTerminated;
}
