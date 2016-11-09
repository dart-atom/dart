
import 'dart:async';
import 'dart:convert' show JSON, JsonCodec, LineSplitter;

import 'package:atom/atom.dart';
import 'package:atom/node/process.dart';
import 'package:atom/utils/dependencies.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';
import 'package:logging/logging.dart';

import '../jobs.dart';
import '../state.dart';
import 'flutter_sdk.dart';

final Logger _logger = new Logger('flutter_daemon');

const _verbose = false;

class FlutterDaemonManager implements Disposable {
  FlutterDaemon _daemon;
  Disposables _disposables = new Disposables();
  StreamSubscription _sub;

  StreamController<FlutterDaemon> _daemonController = new StreamController.broadcast();
  StreamController<Device> _deviceAddedController = new StreamController.broadcast();
  StreamController<Device> _deviceChangedController = new StreamController.broadcast();
  StreamController<Device> _deviceRemovedController = new StreamController.broadcast();

  FlutterDaemonManager() {
    _initFromSdk(_sdkManager.sdk, quiet: true);
    _sub = _sdkManager.onSdkChange.listen(_initFromSdk);
    _disposables.add(atom.commands.add('atom-workspace', 'flutter:restart-daemon', (_) {
      _restartDaemon();
    }));
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

  void _initFromSdk(FlutterSdk sdk, {bool quiet: false}) {
    if (sdk == null) {
      _killFlutterDaemon(quiet: quiet);
    } else if (_daemon == null) {
      _startFlutterDaemon(quiet: quiet);
    }
  }

  void _restartDaemon() {
    if (!_sdkManager.hasSdk) {
      atom.notifications.addWarning('No Flutter SDK configured.');
    } else {
      _killFlutterDaemon();
      _startFlutterDaemon();
    }
  }

  void _killFlutterDaemon({bool quiet: false}) {
    if (_daemon == null) return;

    if (!quiet) atom.notifications.addInfo('Flutter Daemon shutting down.');
    _logger.info('Stopping Flutter daemon server');

    _daemon.dispose();
    _daemon = null;
    _daemonController.add(daemon);
  }

  void _startFlutterDaemon({bool quiet: false}) {
    if (_sdkManager.sdk == null || _daemon != null) return;

    if (!quiet) atom.notifications.addSuccess('Flutter Daemon starting up.');
    _logger.info('Starting Flutter daemon server');

    FlutterTool flutter = _sdkManager.sdk.flutterTool;
    ProcessRunner process = flutter.runRaw(['daemon'], startProcess: true);

    var writeMessage = (String str) {
      process.write('[${str}]\n');
    };

    Stream<String> stream = process.onStdout
      .transform(const LineSplitter())
      .where((String str) => str.startsWith('[') && str.endsWith(']'))
      .map((String str) => str.substring(1, str.length - 1));

    process.onExit.then((_) {
      _daemon?.dispose();
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

    _daemon.device.enable();

    _daemon.onSend.listen((String message) {
      if (_verbose || _logger.isLoggable(Level.FINER)) {
        _logger.fine('--> ${message}');
      }
    });

    _daemon.onReceive.listen((String message) {
      if (_verbose || _logger.isLoggable(Level.FINER)) {
        _logger.fine('<-- ${message}');
      }
    });

    _daemonController.add(daemon);
  }

  void dispose() {
    _disposables.dispose();
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
        if (event == null) {
          _logger.severe('invalid message: ${message}');
        } else {
          String prefix = event.substring(0, event.indexOf('.'));
          if (_domains[prefix] == null) {
            _logger.severe('no domain for notification: ${message}');
          } else {
            _domains[prefix]._handleEvent(event, json['params']);
          }
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

  Stream/*<T>*/ _listen/*<T>*/(String name, Function cvt) {
    if (_streams[name] == null) {
      _controllers[name] = new StreamController/*<T>*/.broadcast();
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

  String toString() => '${error}';
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
    return _listen/*<LogMessage>*/('daemon.logMessage', LogMessage.parse);
  }

  Future<String> version() => _call('daemon.version') as Future<String>;

  Future shutdown() => _call('daemon.shutdown');
}

/// Describes an app running on the device.
class DiscoveredApp {
  final String id;
  final int observatoryPort;

  DiscoveredApp(this.id, this.observatoryPort);
}

class AppDomain extends Domain {
  AppDomain(FlutterDaemon server) : super(server, 'app');

  // app.start; appId, directory, deviceId
  Stream<StartAppEvent> get onAppStart => _listen('app.start', StartAppEvent.parse);

  // app.debugPort; appId, port
  Stream<DebugPortAppEvent> get onAppDebugPort => _listen('app.debugPort', DebugPortAppEvent.parse);

  // app.log; appId, log, [stackTrace], [error](bool)
  Stream<LogAppEvent> get onAppLog => _listen('app.log', LogAppEvent.parse);

  Stream<ProgressAppEvent> get onAppProgress => _listen('app.progress', ProgressAppEvent.parse);

  // app.stop; appId, [error]
  Stream<StopAppEvent> get onAppStop => _listen('app.stop', StopAppEvent.parse);

  /// Start an application on the given device and return an `appId` representing
  /// the running app.
  Future<AppStartedResult> start(
    String deviceId,
    String projectDirectory, {
    bool startPaused,
    String route,
    String mode,
    String target,
    bool enableHotReload: true
  }) {
    return _call('app.start', _stripNullValues({
      'deviceId': deviceId,
      'projectDirectory': projectDirectory,
      'startPaused': startPaused,
      'route': route,
      'mode': mode,
      'target': target,
      'hot': enableHotReload
    })).then((result) {
      return new AppStartedResult(result);
    });
  }

  /// Restart a running flutter app.
  Future<OperationResult> restart(String appId, { bool fullRestart: false }) async {
    dynamic result = await _call('app.restart', _stripNullValues({
      'appId': appId,
      'fullRestart': fullRestart
    }));

    if (result is Map) {
      return new OperationResult(result);
    } else {
      return result == true
        ? OperationResult.ok
        : new OperationResult({ 'code': 1, 'message': fullRestart ? 'restart failed' : 'reload failed' });
    }
  }

  // Stop a running flutter app.
  Future<bool> stop(String appId) {
    return _call('app.stop', {
      'appId': appId
    }) as Future<bool>;
  }

  Future<List<DiscoveredApp>> discover(String deviceId) async {
    List<Map<String, dynamic>> result = await _call(
      'app.discover', _stripNullValues({ 'deviceId': deviceId })
    ) as List<Map<String, dynamic>>;

    return result.map((Map<String, dynamic> app) {
      return new DiscoveredApp(app['id'], app['observatoryDevicePort']);
    });
  }

  DaemonApp createDaemonApp(String appId, { bool supportsRestart: false }) {
    return new DaemonApp(this, appId, supportsRestart: supportsRestart);
  }
}

class DaemonApp {
  final AppDomain daemon;
  final String appId;
  final bool supportsRestart;

  StreamSubscriptions _subs = new StreamSubscriptions();
  Completer _stoppedCompleter = new Completer();
  Completer<DebugPortAppEvent> _debugPortCompleter = new Completer<DebugPortAppEvent>();
  StreamController<LogAppEvent> _logController = new StreamController<LogAppEvent>.broadcast();
  StreamController<ProgressAppEvent> _progressController = new StreamController<ProgressAppEvent>.broadcast();

  DaemonApp(this.daemon, this.appId, { this.supportsRestart: false }) {
    // listen for the debugPort event
    _subs.add(daemon.onAppDebugPort
        .where((AppEvent event) => event.appId == appId)
        .listen((DebugPortAppEvent event) {
      if (!_debugPortCompleter.isCompleted) {
        _debugPortCompleter.complete(event);
      }
    }));

    // listen for logs and progress
    _subs.add(daemon.onAppLog.where((AppEvent event) => event.appId == appId).listen((LogAppEvent event) {
      _logController.add(event);
    }));
    _subs.add(daemon.onAppProgress.where((AppEvent event) => event.appId == appId).listen((ProgressAppEvent event) {
      _progressController.add(event);
    }));

    // listen for app termination
    _subs.add(daemon.onAppStop.where((AppEvent event) => event.appId == appId).listen((_) {
      _dispose();
    }));
  }

  Future<OperationResult> restart({ bool fullRestart: false }) {
    return daemon.restart(appId, fullRestart: fullRestart);
  }

  Future<bool> stop() {
    return daemon.stop(appId).timeout(
      new Duration(seconds: 2),
      onTimeout: () {
        _dispose();
        return true;
      }
    );
  }

  Future<DebugPortAppEvent> get onDebugPort => _debugPortCompleter.future;

  Stream<LogAppEvent> get onAppLog => _logController.stream;

  Stream<ProgressAppEvent> get onAppProgress => _progressController.stream;

  Future get onStopped => _stoppedCompleter.future;

  void _dispose() {
    _subs.cancel();

    if (!_logController.isClosed) {
      _logController.close();
    }

    if (!_progressController.isClosed) {
      _progressController.close();
    }

    if (!_stoppedCompleter.isCompleted) {
      _stoppedCompleter.complete();
    }
  }
}

class AppStartedResult {
  final Map data;

  AppStartedResult(this.data);

  String get appId => data['appId'];
  bool get supportsRestart => data['supportsRestart'];
}

abstract class AppEvent {
  final Map data;

  AppEvent(this.data);

  String get appId => data['appId'];
}

class StartAppEvent extends AppEvent {
  static StartAppEvent parse(Map data) => new StartAppEvent(data);

  StartAppEvent(Map data) : super(data);

  String get directory => data['directory'];
  String get deviceId => data['deviceId'];
  bool get supportsRestart => data['supportsRestart'];
}

class DebugPortAppEvent extends AppEvent {
  static DebugPortAppEvent parse(Map data) => new DebugPortAppEvent(data);

  DebugPortAppEvent(Map data) : super(data);

  int get port => data['port'];

  /// An optional baseUri to resolve and set breakpoints against.
  int get baseUri => data['baseUri'];

  String toString() => '[DebugPortAppEvent: $port, $baseUri]';
}

class LogAppEvent extends AppEvent {
  static LogAppEvent parse(Map data) => new LogAppEvent(data);

  LogAppEvent(Map data) : super(data);

  String get log => data['log'];

  bool get hasStackTrace => data.containsKey('stackTrace');
  String get stackTrace => data['stackTrace'];

  bool get isError => data['error'] ?? false;
}

class ProgressAppEvent extends AppEvent {
  static ProgressAppEvent parse(Map data) => new ProgressAppEvent(data);

  ProgressAppEvent(Map data) : super(data);

  String get message => data['message'];
  bool get isFinished => data['finished'] ?? false;
  String get progressId => data['id'];
}

class StopAppEvent extends AppEvent {
  static StopAppEvent parse(Map data) => new StopAppEvent(data);

  StopAppEvent(Map data) : super(data);

  bool get hasError => data.containsKey('error');
  String get error => data['error'];
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

  Future enable() => _call('device.enable');

  Future disable() => _call('device.disable');

  Future<int> forward(String deviceId, int devicePort, [int hostPort]) {
    return _call('device.forward', _stripNullValues({
      'deviceId': deviceId,
      'devicePort': devicePort,
      'hostPort': hostPort,
    })).then((Map<String, dynamic> result) => result['hostPort']);
  }

  Future unforward(String deviceId, int devicePort, int hostPort) {
    return _call('device.unforward', _stripNullValues({
      'deviceId': deviceId,
      'devicePort': devicePort,
      'hostPort': hostPort,
    }));
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

typedef Future PerformRequest();

/// A [Job] implementation to wrap calls to the daemon server.
class DaemonRequestJob extends Job {
  final PerformRequest _fn;

  DaemonRequestJob(String name, this._fn) : super(toTitleCase(name));

  bool get quiet => true;

  Future run() {
    return _fn().catchError((e) {
      if (e is RequestError) {
        _logger.warning('${name} ${e.methodName} ${e.error}', e);
        atom.notifications.addError('${name} error', detail: '${e.error}');
        return null;
      } else {
        throw e;
      }
    });
  }
}

class OperationResult {
  static final OperationResult ok = new OperationResult({ 'code': 0, 'message': 'ok' });
  final Map m;

  OperationResult(this.m);

  int get code => m['code'];
  String get message => m['message'];

  bool get isOk => code == 0 || code == null;
  bool get isError => !isOk;
}
