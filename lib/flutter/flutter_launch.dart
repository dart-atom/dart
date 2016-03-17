library atom.flutter.flutter_launch;

import 'dart:async';

import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:logging/logging.dart';

import '../debug/debugger.dart';
import '../debug/observatory_debugger.dart' show ObservatoryDebugger;
import '../flutter/flutter_devices.dart';
import '../launch/launch.dart';
import '../projects.dart';
import '../state.dart';
import 'flutter_sdk.dart';

final Logger _logger = new Logger('atom.flutter_launch');

const String _toolName = 'flutter';

FlutterSdkManager _flutterSdk = deps[FlutterSdkManager];

class FlutterLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new FlutterLaunchType());

  _LaunchInstance _lastLaunch;

  FlutterLaunchType([String launchType = 'flutter']) : super(launchType);

  String get flutterRunCommand => 'run';

  bool canLaunch(String path, LaunchData data) {
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return false;

    if (!_flutterSdk.hasSdk) return false;

    // TODO: The file [path] should also import package:flutter.
    return data.hasMain && project.isFlutterProject();
  }

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    String path = configuration.primaryResource;
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return new Future.error("File not in a Dart project.");

    if (!_flutterSdk.hasSdk) {
      _flutterSdk.showInstallationInfo();
      return new Future.error("Unable to launch ${configuration.shortResourceName}; "
        " no Flutter SDK found.");
    }

    return _killLastLaunch().then((_) {
      _lastLaunch = new _LaunchInstance(project, configuration, this);
      return _lastLaunch.launch();
    });
  }

  String getDefaultConfigText() {
    return '''
# Enable or disable checked mode.
checked: true
# Enable or disable debugging.
debug: true
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

class _LaunchInstance {
  final DartProject project;

  Launch _launch;
  ProcessRunner _runner;
  int _observatoryPort;
  List<String> _args;
  Device _device;

  _LaunchInstance(
    this.project,
    LaunchConfiguration configuration,
    FlutterLaunchType launchType
  ) {
    List<String> flutterArgs = configuration.argsAsList;

    // Use either `flutter run` or `flutter run_mojo`.
    _args = [launchType.flutterRunCommand];

    var checked = configuration.typeArgs['checked'];
    if (checked is bool) {
      _args.add(checked ? '--checked' : '--no-checked');
    }

    if (configuration.debug) {
      _observatoryPort = getOpenPort();
      _args.add('--debug-port=${_observatoryPort}');
      _args.add('--start-paused');
    }

    var route = configuration.typeArgs['route'];
    if (route is String && route.isNotEmpty) {
      _args.add('--route');
      _args.add(route);
    }

    _device = _currentSelectedDevice;
    if (_device != null) {
      _args.add('--device-id');
      _args.add(_device.id);
    }

    String relPath = fs.relativize(project.path, configuration.primaryResource);
    if (relPath != 'lib/main.dart') {
      _args.add('-t');
      _args.add(relPath);
    }

    _args.addAll(flutterArgs);

    String description = '${_toolName} ${_args.join(' ')} • ${_toolName} logs';

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
    FlutterTool flutter = _flutterSdk.sdk.flutterTool;

    // Chain together both 'flutter run' and 'flutter logs'.
    _runner = _flutter(flutter, _args, cwd: project.path);
    _runner.execStreaming();
    _runner.onStdout.listen((str) => _launch.pipeStdio(str));
    _runner.onStderr.listen((str) => _launch.pipeStdio(str, error: true));

    int code = await _runner.onExit;
    if (code == 0) {
      if (_observatoryPort != null) {
        new Future.delayed(new Duration(milliseconds: 100), () {
          FlutterUriTranslator translator = new FlutterUriTranslator(_launch.project?.path);
          ObservatoryDebugger.connect(
            _launch,
            'localhost',
            _observatoryPort,
            uriTranslator: translator
          ).then((_) {
            _launch.servicePort.value = _observatoryPort;
          }).catchError((e) {
            _launch.pipeStdio(
              'Unable to connect to the Observatory at port ${_observatoryPort}.\n',
              error: true
            );
          });
        });
      }

      // Chain 'flutter logs'.
      List<String> logsArgs = ['logs'];

      // Just log from the currently selected device.
      if (_device != null) {
        logsArgs.add('--device-id');
        logsArgs.add(_device.id);
      }

      _runner = _flutter(flutter, logsArgs, cwd: project.path);
      _runner.execStreaming();
      _runner.onStdout.listen((str) => _launch.pipeStdio(str));
      _runner.onStderr.listen((str) => _launch.pipeStdio(str, error: true));

      // Don't return the future here.
      _runner.onExit.then((code) => _launch.launchTerminated(code));
    } else {
      _launch.launchTerminated(code);
    }

    return _launch;
  }

  Future _kill() {
    if (_runner == null) {
      _launch.launchTerminated(1);
      return new Future.value();
    } else {
      // Run flutter stop.
      FlutterTool flutter = _flutterSdk.sdk.flutterTool;

      List args = ['stop'];

      if (_device != null) {
        args.add('--device-id');
        args.add(_device.id);
      }

      ProcessRunner flutterStop = _flutter(flutter, args, cwd: project.path);
      flutterStop.execSimple().catchError((e) {
        _logger.finer('Error from flutter stop', e);
      });

      // And kill the logging process.
      return _runner.kill();
    }
  }

  Device get _currentSelectedDevice {
    FlutterDeviceManager deviceManager = deps[FlutterDeviceManager];
    return deviceManager.currentSelectedDevice;
  }
}

ProcessRunner _flutter(FlutterTool flutter, List<String> args, {String cwd}) {
  return flutter.runRaw(args, cwd: cwd, startProcess: false);
}

// TODO: Move _LaunchInstance functionality into this class?
class _FlutterLaunch extends Launch {
  CachingServerResolver _resolver;

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
    _resolver = new CachingServerResolver(
      cwd: project.path,
      server: analysisServer
    );

    exitCode.onChanged.first.then((_) => _resolver.dispose());
  }

  // TODO: Use the device name?
  String get locationLabel => project.workspaceRelativeName;

  Future<String> resolve(String url) => _resolver.resolve(url);
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
