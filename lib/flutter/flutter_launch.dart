
import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:logging/logging.dart';

import '../debug/debugger.dart';
import '../debug/observatory_debugger.dart' show ObservatoryDebugger;
import '../flutter/flutter_devices.dart';
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

  _LaunchInstance _lastLaunch;

  FlutterLaunchType([String launchType = 'flutter']) : super(launchType);

  bool get supportsChecked => false;

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

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    String path = configuration.primaryResource;
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return new Future.error("File not in a Dart project.");

    if (!_flutterSdk.hasSdk) {
      _flutterSdk.showInstallationInfo();
      return new Future.error("Unable to launch application; no Flutter SDK found.");
    }

    // Check that the flutter daemon is running.
    if (flutterDaemon == null) {
      return new Future.error("Unable to launch application; "
        "the Flutter daemon is not running. Make sure a Flutter SDK is configured in the "
        "settings for the 'flutter' plugin and / or try re-starting Atom.");
    }

    return _killLastLaunch().then((_) {
      _lastLaunch = new _RunLaunchInstance(project, configuration, this, flutterDaemon);
      return _lastLaunch.launch();
    });
  }

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

    _killLastLaunch().then((_) {
      _lastLaunch = new _ConnectLaunchInstance(
        project,
        configuration,
        this,
        observatoryPort,
        pipeStdio: pipeStdio
      );
      _lastLaunch.launch();
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

  Future _killLastLaunch() {
    if (_lastLaunch == null) return new Future.value();
    Launch launch = _lastLaunch._launch;
    return launch.isTerminated ? new Future.value() : launch.kill();
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
    return daemon.app.start(
      _device?.id,
      project.path,
      mode: _mode.name,
      startPaused: _mode.startPaused,
      target: _target,
      route: _route
    ).then((AppStartedResult result) {
      _app = daemon.app.createDaemonApp(result.appId, supportsRestart: result.supportsRestart);
      _launch.app = _app;

      launchManager.addLaunch(_launch);

      _LogStatusJob job;

      _app.onDebugPort.then((DebugPortAppEvent event) {
        _observatoryPort = event.port;
        new Future.delayed(new Duration(milliseconds: 100), _connectToDebugger);
      });

      _app.onAppLog.listen((LogAppEvent log) {
        if (log.isProgress) {
          if (!log.isProgressFinished) {
            job?.cancel();

            job = new _LogStatusJob(log.log);
            job.schedule();
          } else {
            job?.cancel();
          }
        } else {
          _launch.pipeStdio('${log.log}\n', error: log.isError);
          if (log.hasStackTrace) _launch.pipeStdio('${log.stackTrace}\n', error: true);
        }
      });

      _app.onStopped.then((_) {
        job?.cancel();
        _launch.launchTerminated(0);
      });

      return _launch;
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

  Future restart() {
    return app.restart().then((bool result) {
      if (!result) {
        atom.notifications.addWarning('Error restarting application.');
      }
    });
  }

  Future<String> resolve(String url) => resolver.resolve(url);
}

class FlutterUriTranslator implements UriTranslator {
  static const _packagesPrefix = 'packages/';
  static const _packagePrefix = 'package:';

  final String root;

  FlutterUriTranslator(this.root);

  String targetToClient(String str) {
    String result = _targetToClient(str);
    _logger.finer('targetToClient ${str} ==> ${result}');
    return result;
  }

  String _targetToClient(String str) {
    if (str.startsWith(_packagesPrefix)) {
      // Convert packages/ prefix to package: one.
      return _packagePrefix + str.substring(_packagesPrefix.length);
    } else if (fs.existsSync(str)) {
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
    if (str.startsWith(_packagePrefix)) {
      // Convert package: prefix to packages/ one.
      return _packagesPrefix + str.substring(_packagePrefix.length);
    } else if (str.startsWith('file:')) {
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
