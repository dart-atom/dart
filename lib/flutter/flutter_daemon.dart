
import 'dart:async';
import 'dart:convert' show JSON, JsonCodec, LineSplitter;

import 'package:logging/logging.dart';

import '../process.dart';
import '../state.dart';
import '../utils.dart';
import 'flutter_sdk.dart';

final Logger _logger = new Logger('flutter_daemon');

class FlutterDaemonManager implements Disposable {
  FlutterDaemon _daemon;
  StreamSubscription _sub;

  StreamController<FlutterDaemon> _daemonController = new StreamController.broadcast();
  StreamController<Device> _deviceAddedController = new StreamController.broadcast();
  StreamController<Device> _deviceChangedController = new StreamController.broadcast();
  StreamController<Device> _deviceRemovedController = new StreamController.broadcast();

  FlutterDaemonManager() {
    _initSdk(_sdkManager.sdk);
    _sub = _sdkManager.onSdkChange.listen(_initSdk);
  }

  FlutterDaemon get daemon => _daemon;

  Stream<FlutterDaemon> get onDaemonAvailable => _daemonController.stream;

  Stream<Device> get onDeviceAdded => _deviceAddedController.stream;
  Stream<Device> get onDeviceChanged => _deviceChangedController.stream;
  Stream<Device> get onDeviceRemoved => _deviceRemovedController.stream;

  Future<List<Device>> getDevices() {
    return daemon == null ? new Future.value([]) : daemon.device.getDevices();
  }

  FlutterSdkManager get _sdkManager => deps[FlutterSdkManager];

  void _initSdk(FlutterSdk sdk) {
    if (sdk == null) {
      if (_daemon != null) {
        _logger.info('Stopping Flutter daemon server');
        _daemon.dispose();
        _daemon = null;

        _daemonController.add(daemon);
      }
    } else {
      FlutterTool flutter = sdk.flutterTool;

      _logger.info('Starting Flutter daemon server');
      ProcessRunner process = flutter.runRaw(['daemon'], startProcess: true);

      var writeMessage = (String str) {
        process.write('[${str}]\n');
      };

      Stream<String> stream = process.onStdout
        .transform(const LineSplitter())
        .where((String str) => str.startsWith('[') && str.endsWith(']'))
        .map((String str) => str.substring(1, str.length - 1));

      process.onExit.then((_) {
        _daemon.dispose();
        _daemon = null;

        _daemonController.add(daemon);
      });

      _daemon = new FlutterDaemon(
        stream,
        writeMessage,
        otherDisposeable: new _ProcessDisposable(process)
      );

      _daemon.daemon.onLogMessage.listen((LogMessage message) {
        switch (message.level) {
          case 'error':
            if (message.stackTrace != null) {
              _logger.severe(message.message, null, new StackTrace.fromString(message.stackTrace));
            } else {
              _logger.severe(message.message);
            }
            break;
          case 'status':
            _logger.info(message.message);
            break;
          default:
            // 'trace'
            _logger.finer(message.message);
            break;
        }
      });

      _daemon.device.onDeviceAdded.listen((Device device) {
        _deviceAddedController.add(device);
      });
      _daemon.device.onDeviceChanged.listen((Device device) {
        _deviceChangedController.add(device);
      });
      _daemon.device.onDeviceRemoved.listen((Device device) {
        _deviceRemovedController.add(device);
      });

      _daemon.onSend.listen((String message) {
        if (_logger.isLoggable(Level.FINER)) {
          _logger.finer('--> ${message}');
        }
      });

      _daemon.onReceive.listen((String message) {
        if (_logger.isLoggable(Level.FINER)) {
          _logger.finer('<-- ${message}');
        }
      });

      _daemonController.add(daemon);
    }
  }

  void dispose() {
    _daemon?.dispose();
    _sub?.cancel();
  }
}

class _ProcessDisposable implements Disposable {
  final ProcessRunner process;

  _ProcessDisposable(this.process);

  void dispose() {
    if (!process.finished) process.kill();
  }
}

class FlutterDaemon {
  final Disposable otherDisposeable;

  StreamSubscription _streamSub;
  Function _writeMessage;
  int _id = 0;
  Map<String, Completer> _completers = {};
  Map<String, String> _methodNames = {};
  JsonCodec _jsonEncoder = new JsonCodec(toEncodable: _toEncodable);
  Map<String, Domain> _domains = {};
  StreamController<String> _onSend = new StreamController.broadcast();
  StreamController<String> _onReceive = new StreamController.broadcast();
  Function _willSend;

  DaemonDomain _daemon;
  AppDomain _app;
  DeviceDomain _device;

  FlutterDaemon(
    Stream<String> inStream,
    void writeMessage(String message), {
    this.otherDisposeable
  }) {
    _streamSub = inStream.listen(_processMessage);
    _writeMessage = writeMessage;

    _daemon = new DaemonDomain(this);
    _app = new AppDomain(this);
    _device = new DeviceDomain(this);
  }

  DaemonDomain get daemon => _daemon;
  AppDomain get app => _app;
  DeviceDomain get device => _device;

  Stream<String> get onSend => _onSend.stream;
  Stream<String> get onReceive => _onReceive.stream;

  set willSend(void fn(String methodName)) {
    _willSend = fn;
  }

  void dispose() {
    if (_streamSub != null) _streamSub.cancel();
    //_completers.values.forEach((c) => c.completeError('disposed'));
    _completers.clear();
    otherDisposeable?.dispose();
  }

  void _processMessage(String message) {
    try {
      _onReceive.add(message);

      var json = JSON.decode(message);

      if (json['id'] == null) {
        // Handle a notification.
        String event = json['event'];
        String prefix = event.substring(0, event.indexOf('.'));
        if (_domains[prefix] == null) {
          _logger.severe('no domain for notification: ${message}');
        } else {
          _domains[prefix]._handleEvent(event, json['params']);
        }
      } else {
        Completer completer = _completers.remove(json['id']);
        String methodName = _methodNames.remove(json['id']);

        if (completer == null) {
          _logger.severe('unmatched request response: ${message}');
        } else if (json['error'] != null) {
          completer.completeError(new RequestError(methodName, json['error']));
        } else {
          completer.complete(json['result']);
        }
      }
    } catch (e) {
      _logger.severe('unable to decode message: ${message}, ${e}');
    }
  }

  Future<dynamic> _call(String method, [Map args]) {
    String id = '${++_id}';
    _completers[id] = new Completer();
    _methodNames[id] = method;
    Map m = {'id': id, 'method': method};
    if (args != null) m['params'] = args;
    String message = _jsonEncoder.encode(m);
    if (_willSend != null) _willSend(method);
    _onSend.add(message);
    _writeMessage(message);
    return _completers[id].future;
  }

  static dynamic _toEncodable(obj) => obj is Jsonable ? obj.toMap() : obj;
}

abstract class Domain {
  final FlutterDaemon server;
  final String name;

  Map<String, StreamController> _controllers = {};
  Map<String, Stream> _streams = {};

  Domain(this.server, this.name) {
    server._domains[name] = this;
  }

  Future<dynamic> _call(String method, [Map args]) => server._call(method, args);

  Stream<dynamic> _listen(String name, Function cvt) {
    if (_streams[name] == null) {
      _controllers[name] = new StreamController.broadcast();
      _streams[name] = _controllers[name].stream.map(cvt);
    }

    return _streams[name];
  }

  void _handleEvent(String name, dynamic event) {
    if (_controllers[name] != null) {
      _controllers[name].add(event);
    }
  }

  String toString() => 'Domain ${name}';
}

abstract class Jsonable {
  Map toMap();
}

class RequestError {
  final String methodName;
  final dynamic error;

  RequestError(this.methodName, this.error);

  String toString() => '[RequestError ${error}]';
}

/// Create a copy of the given map with all `null` values stripped out.
Map _stripNullValues(Map m) {
  Map copy = {};

  for (var key in m.keys) {
    var value = m[key];
    if (value != null) copy[key] = value;
  }

  return copy;
}

class DaemonDomain extends Domain {
  DaemonDomain(FlutterDaemon server) : super(server, 'daemon');

  Stream<LogMessage> get onLogMessage {
    return _listen('daemon.logMessage', LogMessage.parse);
  }

  Future<String> version() => _call('daemon.version');

  Future shutdown() => _call('daemon.shutdown');
}

class AppDomain extends Domain {
  AppDomain(FlutterDaemon server) : super(server, 'app');

  // TODO: result
  // TODO: We need the stdout and stderr from launching the process.
  Future<dynamic> start(
    String projectDirectory, {
    String target,
    bool checked,
    String route
  }) {
    return _call('app.start', _stripNullValues({
      'projectDirectory': projectDirectory,
      'target': target,
      'checked': checked,
      'route': route
    }));
  }

  Future<bool> stopAll() => _call('app.stopAll');
}

class DeviceDomain extends Domain {
  DeviceDomain(FlutterDaemon server) : super(server, 'device');

  Stream<Device> get onDeviceAdded {
    return _listen('device.added', Device.parse);
  }

  Stream<Device> get onDeviceRemoved {
    return _listen('device.removed', Device.parse);
  }

  Stream<Device> get onDeviceChanged {
    return _listen('device.changed', Device.parse);
  }

  Future<List<Device>> getDevices() {
    return _call('device.getDevices').then((List result) {
      return result.map(Device.parse).toList();
    });
  }
}

class Device {
  static Device parse(Map m) {
    return new Device(m['id'], m['name'], m['platform'], m['available']);
  }

  final String id;
  final String name;
  final String platform;
  final bool available;

  Device(this.id, this.name, this.platform, this.available);

  String get platformLabel => platform == 'android' ? 'Android' : platform;

  String getLabel() {
    if (name != null) return name;
    return '$platformLabel $id';
  }

  operator == (other) => other is Device && id == other.id;

  int get hashCode => id.hashCode;

  String toString() => '[$id, $name, $platform]';
}

class LogMessage {
  static LogMessage parse(Map m) {
    return new LogMessage(m['level'], m['message'], m['stackTrace']);
  }

  final String level;
  final String message;
  final String stackTrace;

  LogMessage(this.level, this.message, [this.stackTrace]);

  String toString() => '[$level] $message';
}
