import 'dart:async';
import 'dart:js';

import 'package:atom/node/node.dart';

// TODO: This class should move into `package:atom`.

class WebSocket {
  static JsFunction _WebSocket = require('ws');

  JsObject _ws;

  WebSocket(String url) {
    // TODO(devoncarew): We could also pass in the origin here.
    _ws = _WebSocket.apply([url]);
  }

  Stream<Null> get onOpen {
    StreamController<Null> controller = new StreamController.broadcast();
    _ws.callMethod('on', ['open', () => controller.add(null)]);
    return controller.stream;
  }

  Stream<MessageEvent> get onMessage {
    StreamController<MessageEvent> controller = new StreamController<MessageEvent>.broadcast();
    _ws.callMethod('on', ['message', (data, flags) {
      controller.add(new MessageEvent(data, flags));
    }]);
    return controller.stream;
  }

  Stream<dynamic> get onError {
    StreamController controller = new StreamController.broadcast();
    _ws.callMethod('on', ['error', (event) => controller.add(event)]);
    return controller.stream;
  }

  Stream<dynamic> get onClose {
    StreamController controller = new StreamController.broadcast();
    _ws.callMethod('on', ['close', (code, message) => controller.add(code)]);
    return controller.stream;
  }

  void send(String data) {
    _ws.callMethod('send', [data]);
  }

  void close() {
    _ws.callMethod('close');
  }
}

class MessageEvent {
  final dynamic data;
  final dynamic flags;

  MessageEvent(this.data, this.flags);
}
