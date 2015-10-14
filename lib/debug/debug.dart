library atom.debug;

import 'dart:async';

import 'package:logging/logging.dart';

import '../launch.dart';
import '../utils.dart';
import 'debug_ui.dart';

final Logger _logger = new Logger('atom.debug');

// TODO: Track current debug target - fire when it changes.

class DebugManager implements Disposable {
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
  }

  Stream<DebugConnection> get onAdded => _addedController.stream;

  Stream<DebugConnection> get onRemoved => _removedController.stream;

  void addConnection(DebugConnection connection) {
    connections.add(connection);
    _addedController.add(connection);
  }

  void removeConnection(DebugConnection connection) {
    connections.remove(connection);
    _removedController.add(connection);
  }

  void dispose() {
    // TODO:
  }
}

abstract class DebugConnection {
  final Launch launch;

  DebugConnection(this.launch);

  pause();
  resume();
  stepIn();
  stepOver();
  stepOut();
  terminate();

  Future get onTerminated;
}
