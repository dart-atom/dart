/// A library to interface with the flutter tool's daemon server.
library atom.flutter_daemon;

import 'dart:async';
import 'dart:convert' show JSON, JsonCodec;

import 'package:logging/logging.dart';

final Logger _logger = new Logger('atom.flutter_daemon');

class FlutterDaemon {
  static Future<FlutterDaemon> start(String path) {
    // TODO: start the app; hook up stdout and stdin

    // Stream<Map> commandStream = stdin
    //   .transform(UTF8.decoder)
    //   .transform(const LineSplitter())
    //   .where((String line) => line.startsWith('[{') && line.endsWith('}]'))
    //   .map((String line) {
    //     line = line.substring(1, line.length - 1);
    //     return JSON.decode(line);
    //   });

    return new FlutterDaemon._(null, null);
  }

  int _id = 0;
  Map<String, Completer> _completers = {};
  Map<String, Domain> _domains = {};
  JsonCodec _jsonEncoder = new JsonCodec();

  DaemonDomain _daemon;
  AppDomain _app;

  final Stream<Map> _in;
  final Sink<String> _out;

  FlutterDaemon._(this._in, this._out) {
    _daemon = new DaemonDomain(this);
    _app = new AppDomain(this);

    _in.listen(_processMessage);
  }

  DaemonDomain get daemon => _daemon;
  AppDomain get app => _app;

  Future _call(String method, [Map args]) {
    String id = '${++_id}';
    _completers[id] = new Completer();
    Map m = {'id': id, 'method': method};
    if (args != null) m['params'] = args;
    //_onSend.add(message);
    _writeMessage(m);
    return _completers[id].future;
  }

  void _processMessage(Map message) {
    try {
      //_onReceive.add(message);

      if (message['id'] == null) {
        // Handle a notification.
        String event = message['event'];
        String prefix = event.substring(0, event.indexOf('.'));
        if (_domains[prefix] == null) {
          _logger.severe('no domain for notification: ${message}');
        } else {
          _domains[prefix]._handleEvent(event, message['params']);
        }
      } else {
        Completer completer = _completers.remove(message['id']);

        if (completer == null) {
          _logger.severe('unmatched request response: ${message}');
        } else if (message['error'] != null) {
          completer.completeError(message['error']);
        } else {
          completer.complete(message['result']);
        }
      }
    } catch (e) {
      _logger.severe('unable to decode message: ${message}, ${e}');
    }
  }

  void _writeMessage(Map message) {
    _out.add('[${_jsonEncoder.encode(message)}]');
  }
}

abstract class Domain {
  final FlutterDaemon server;
  final String name;

  Map<String, StreamController> _controllers = {};
  // Map<String, Stream> _streams = {};

  Domain(this.server, this.name) {
    server._domains[name] = this;
  }

  Future _call(String method, [Map args]) => server._call(method, args);

  // Stream<dynamic> _listen(String name, Function cvt) {
  //   if (_streams[name] == null) {
  //     _controllers[name] = new StreamController.broadcast();
  //     _streams[name] = _controllers[name].stream.map(cvt);
  //   }
  //
  //   return _streams[name];
  // }

  void _handleEvent(String name, dynamic event) {
    if (_controllers[name] != null) {
      _controllers[name].add(event);
    }
  }

  String toString() => 'Domain ${name}';
}

class DaemonDomain extends Domain {
  DaemonDomain(FlutterDaemon server) : super(server, 'daemon');

  Future<String> version() => _call('daemon.getVersion');
  Future shutdown() => _call('daemon.shutdown');
}

class AppDomain extends Domain {
  AppDomain(FlutterDaemon server) : super(server, 'app');

  Future start() => _call('app.start');
  Future stopAll() => _call('app.stopAll');
}
