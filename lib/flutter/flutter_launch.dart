
import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:logging/logging.dart';

import '../debug/debugger.dart';
import '../debug/observatory_debugger.dart' show ObservatoryDebugger;
import '../flutter/flutter_devices.dart';
import '../flutter/flutter_daemon.dart';
import '../jobs.dart';
import '../launch/launch.dart';
import '../projects.dart';
import '../state.dart';
import 'flutter_daemon.dart';
import 'flutter_sdk.dart';

final Logger _logger = new Logger('atom.flutter_launch');

FlutterSdkManager _flutterSdk = deps[FlutterSdkManager];

FlutterDeviceManager get deviceManager => deps[FlutterDeviceManager];
FlutterDaemonManager get flutterDaemonManager => deps[FlutterDaemonManager];
FlutterDaemon get flutterDaemon => flutterDaemonManager.daemon;

class FlutterLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new FlutterLaunchType());

  FlutterLaunchType([String launchType = 'flutter']) : super(launchType);

  bool get supportsChecked => false;

  bool get supportsDebugArg => false;

  bool canLaunch(String path, LaunchData data) {
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return false;

    if (!_flutterSdk.hasSdk) return false;

    // It's a flutter entry-point if it's in a Flutter project, has a main()
    // method, and imports a flutter package.
    if (data.hasMain && project.isFlutterProject()) {
      if (data.fileContents != null) {
        return data.fileContents.contains('"package:flutter/')
          || data.fileContents.contains("'package:flutter/");
      }
    }

    return false;
  }

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) async {
    String path = configuration.primaryResource;
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) throw "File not in a Dart project.";

    if (!_flutterSdk.hasSdk) {
      _flutterSdk.showInstallationInfo();
      throw "Unable to launch application; no Flutter SDK found.";
    }

    // Check that the flutter daemon is running.
    if (flutterDaemon == null) {
      return throw "Unable to launch application; "
        "the Flutter daemon is not running. Make sure a Flutter SDK is configured in the "
        "settings for the 'flutter' plugin and / or try re-starting Atom.";
    }

    if (_lastFlutterLaunch != null) {
      // Instead of killing the last launch, check if we should re-start it.
      if (_lastFlutterLaunch.launchConfiguration == configuration) {
        if (!_lastFlutterLaunch.isTerminated && _lastFlutterLaunch.supportsRestart) {
          await _lastFlutterLaunch.restart();
          return _lastFlutterLaunch;
        }
      }

      // Terminate any existing Flutter launch.
      await _killLaunch(_lastFlutterLaunch);
    }

    _RunLaunchInstance newLaunch = new _RunLaunchInstance(project, configuration, this, flutterDaemon);
    _lastFlutterLaunch = newLaunch._launch;
    return newLaunch.launch();
  }

  _FlutterLaunch _lastFlutterLaunch;

  void connectToApp(
    DartProject project,
    LaunchConfiguration configuration,
    int observatoryPort, {
    bool pipeStdio: true
  }) {
    if (!_flutterSdk.hasSdk) {
      _flutterSdk.showInstallationInfo();
      return;
    }

    _killLaunch(_lastFlutterLaunch).then((_) {
      _ConnectLaunchInstance newLaunch = new _ConnectLaunchInstance(
        project,
        configuration,
        this,
        observatoryPort,
        pipeStdio: pipeStdio
      );
      _lastFlutterLaunch = newLaunch._launch;
      newLaunch.launch();
    });
  }

  String getDefaultConfigText() {
    return '''
# The starting route for the app.
route:
# Additional args for the flutter run command.
args:
''';
  }

  Future _killLaunch(Launch launch) async {
    if (launch == null || launch.isTerminated) return null;

    await launch.kill();

    // flutter_tools is not happy with two applications running at once
    // (they each have their own notion of a cwd).
    await new Future.delayed(new Duration(milliseconds: 500));
  }
}

abstract class _LaunchInstance {
  final DartProject project;
  _FlutterLaunch _launch;
  int _observatoryPort;
  Device _device;
  DebugConnection debugConnection;

  _LaunchInstance(this.project) {
    _device = deviceManager.currentSelectedDevice;
  }

  bool get pipeStdio;

  Future<Launch> launch();

  void _connectToDebugger() {
    FlutterUriTranslator translator = new FlutterUriTranslator(_launch.project?.path);

    ObservatoryDebugger.connect(
      _launch,
      'localhost',
      _observatoryPort,
      uriTranslator: translator,
      pipeStdio: pipeStdio
    ).then((DebugConnection connection) {
      debugConnection = connection;
      _launch.servicePort.value = _observatoryPort;
    }).catchError((e) {
      _launch.pipeStdio(
        'Unable to connect to the Observatory at port ${_observatoryPort}.\n',
        error: true
      );
    });
  }
}

class _RunLaunchInstance extends _LaunchInstance {
  final FlutterDaemon daemon;

  BuildMode _mode;
  String _route;
  String _target;

  DaemonApp _app;

  _RunLaunchInstance(
    DartProject project,
    LaunchConfiguration configuration,
    FlutterLaunchType launchType,
    this.daemon
  ) : super(project) {
    _mode = deviceManager.runMode;

    _route = configuration.typeArgs['route'];
    if (_route != null && _route.isEmpty) _route = null;

    _target = fs.relativize(project.path, configuration.primaryResource);

    _launch = new _FlutterLaunch(
      launchManager,
      launchType,
      configuration,
      configuration.shortResourceName,
      project,
      killHandler: _kill,
      cwd: project.path,
      title: 'flutter run ${_target} ($_mode)',
      targetName: _device?.name
    );
  }

  bool get pipeStdio => false;

  Future<Launch> launch() async {
    bool enableHotReload = atom.config.getValue('flutter.enableHotReload');

    return daemon.app.start(
      _device?.id,
      project.path,
      mode: _mode.name,
      startPaused: _mode.startPaused,
      target: _target,
      route: _route,
      enableHotReload: enableHotReload
    ).then((AppStartedResult result) {
      _app = daemon.app.createDaemonApp(result.appId, supportsRestart: result.supportsRestart);
      _launch.app = _app;

      launchManager.addLaunch(_launch);

      _LogStatusJob job;

      _app.onDebugPort.then((DebugPortAppEvent event) {
        _observatoryPort = event.port;
        _connectToDebugger();
      });

      _app.onAppLog.listen((LogAppEvent log) {
        _launch.pipeStdio('${log.log}\n', error: log.isError);
        if (log.hasStackTrace) _launch.pipeStdio('${log.stackTrace}\n', error: true);
      });

      _app.onAppProgress.listen((ProgressAppEvent log) {
        if (!log.isFinished) {
          job?.cancel();

          job = new _LogStatusJob(log.message);
          job.schedule();
        } else {
          job?.cancel();
        }
      });

      _app.onStopped.then((_) {
        job?.cancel();
        _launch.launchTerminated(0);
      });

      return _launch;
    }).catchError((e) {
      if (e is RequestError && e.error == 'deviceId is required') {
        throw new RequestError(e.methodName, 'No target device available.');
      } else {
        throw e;
      }
    });
  }

  Future _kill() {
    if (_app == null) {
      _launch.launchTerminated(0);
      return new Future.value();
    } else {
      return _app.stop().whenComplete(() {
        _app = null;
      }).catchError((e) => null);
    }
  }
}

/// A Job used to show progress to the user for flutter daemon reported tasks.
class _LogStatusJob extends Job {
  Completer completer = new Completer();

  _LogStatusJob(String message) : super(_stripEllipses(message));

  bool get quiet => true;

  @override
  Future run() => completer.future;

  void dispose() {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  static String _stripEllipses(String str) {
    return str.endsWith('...') ? str.substring(0, str.length - 3) : str;
  }
}

class _ConnectLaunchInstance extends _LaunchInstance {
  int _observatoryDevicePort;
  bool pipeStdio;

  _ConnectLaunchInstance(
    DartProject project,
    LaunchConfiguration configuration,
    FlutterLaunchType launchType,
    this._observatoryDevicePort, {
    this.pipeStdio
  }) : super(project) {
    String description = 'Flutter connect to port $_observatoryDevicePort';

    _launch = new _FlutterLaunch(
      launchManager,
      launchType,
      configuration,
      configuration.shortResourceName,
      project,
      killHandler: _kill,
      cwd: project.path,
      title: description,
      targetName: _device?.name
    );
    launchManager.addLaunch(_launch);
  }

  Future<Launch> launch() async {
    _observatoryPort = await flutterDaemon.device.forward(_device.id, _observatoryDevicePort);
    _connectToDebugger();
    return _launch;
  }

  Future _kill() {
    flutterDaemon.device.unforward(_device.id, _observatoryDevicePort, _observatoryPort);
    _launch.launchTerminated(0);
    return new Future.value();
  }
}

// TODO: Move _LaunchInstance functionality into this class?
class _FlutterLaunch extends Launch {
  CachingServerResolver resolver;
  DaemonApp app;

  _FlutterLaunch(
    LaunchManager manager,
    LaunchType launchType,
    LaunchConfiguration launchConfiguration,
    String name,
    DartProject project, {
    Function killHandler,
    String cwd,
    String title,
    String targetName
  }) : super(
    manager,
    launchType,
    launchConfiguration,
    name,
    killHandler: killHandler,
    cwd: cwd,
    title: title,
    targetName: targetName
  ) {
    resolver = new CachingServerResolver(
      cwd: project.path,
      server: analysisServer
    );

    exitCode.onChanged.first.then((_) => resolver.dispose());
  }

  String get locationLabel => project.workspaceRelativeName;

  bool get supportsRestart => app != null && app.supportsRestart;

  Future restart({ bool fullRestart: false }) async {
    if (fullRestart) {
      atom.notifications.addInfo('Performing full restart…');
    }

    return app.restart(fullRestart: fullRestart).then((OperationResult result) {
      if (result.isError) {
        atom.notifications.addWarning(
          'Error restarting application',
          description: result.message
        );
      }
    });
  }

  Future<String> resolve(String url) => resolver.resolve(url);
}

class FlutterUriTranslator implements UriTranslator {
  final String root;

  FlutterUriTranslator(this.root);

  String targetToClient(String str) {
    String result = _targetToClient(str);
    _logger.finer('targetToClient ${str} ==> ${result}');
    return result;
  }

  String _targetToClient(String str) {
    if (fs.existsSync(str)) {
      return new Uri.file(str).toString();
    } else {
      return str;
    }
  }

  String clientToTarget(String str) {
    String result = _clientToTarget(str);
    _logger.finer('clientToTarget ${str} ==> ${result}');
    return result;
  }

  String _clientToTarget(String str) {
    if (str.startsWith('file:')) {
      return Uri.parse(str).toFilePath();
    } else {
      return str;
    }
  }
}

// class FlutterUriTranslator implements UriTranslator {
//   static const _packagesPrefix = 'packages/';
//   static const _packagePrefix = 'package:';
//
//   final String root;
//   final String prefix;
//
//   String _rootPrefix;
//
//   FlutterUriTranslator(this.root, {this.prefix: 'http://localhost:9888/'}) {
//     _rootPrefix = new Uri.directory(root, windows: isWindows).toString();
//   }
//
//   String targetToClient(String str) {
//     String result = _targetToClient(str);
//     _logger.finer('targetToClient ${str} ==> ${result}');
//     return result;
//   }
//
//   String _targetToClient(String str) {
//     if (str.startsWith(prefix)) {
//       str = str.substring(prefix.length);
//
//       if (str.startsWith(_packagesPrefix)) {
//         // Convert packages/ prefix to package: one.
//         return _packagePrefix + str.substring(_packagesPrefix.length);
//       } else {
//         // Return files relative to the starting project.
//         return '${_rootPrefix}${str}';
//       }
//     } else {
//       return str;
//     }
//   }
//
//   String clientToTarget(String str) {
//     String result = _clientToTarget(str);
//     _logger.finer('clientToTarget ${str} ==> ${result}');
//     return result;
//   }
//
//   String _clientToTarget(String str) {
//     if (str.startsWith(_packagePrefix)) {
//       // Convert package: prefix to packages/ one.
//       return prefix + _packagesPrefix + str.substring(_packagePrefix.length);
//     } else if (str.startsWith(_rootPrefix)) {
//       // Convert file:///foo/bar/lib/main.dart to http://.../lib/main.dart.
//       return prefix + str.substring(_rootPrefix.length);
//     } else {
//       return str;
//     }
//   }
// }
