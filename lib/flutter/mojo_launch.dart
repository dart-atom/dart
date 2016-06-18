
import 'dart:async';

import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:logging/logging.dart';

import '../flutter/flutter_devices.dart';
import '../launch/launch.dart';
import '../projects.dart';
import '../state.dart';
import 'flutter_sdk.dart';

final Logger _logger = new Logger('atom.mojo_launch');

FlutterSdkManager _flutterSdk = deps[FlutterSdkManager];
FlutterDeviceManager get deviceManager => deps[FlutterDeviceManager];

class MojoLaunchType extends LaunchType {
  static void register(LaunchManager manager) => manager.registerLaunchType(new MojoLaunchType());

  MojoLaunchType() : super('mojo');

  // Don't advertise the mojo launch configuration as much as the flutter one.
  bool canLaunch(String path, LaunchData data) => false;

  String getDefaultConfigText() {
    return 'checked: true\n# args:\n#  - --mojo-path=path/to/mojo';
  }

  _LaunchInstance _lastLaunch;

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) async {
    String path = configuration.primaryResource;
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) throw "File not in a Dart project.";

    if (!_flutterSdk.hasSdk) {
      _flutterSdk.showInstallationInfo();
      throw "Unable to launch ${configuration.shortResourceName}; no Flutter SDK found.";
    }

    await _killLastLaunch();

    _lastLaunch = new _LaunchInstance(project, configuration, this);
    return _lastLaunch.launch();
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
  List<String> _args;
  Device _device;

  _LaunchInstance(
    this.project,
    LaunchConfiguration configuration,
    MojoLaunchType launchType
  ) {
    List<String> flutterArgs = configuration.argsAsList;

    _args = ['run_mojo'];

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

    _launch = new Launch(
      launchManager,
      launchType,
      configuration,
      configuration.shortResourceName,
      killHandler: _kill,
      cwd: project.path,
      title: 'flutter ${_args.join(' ')}',
      targetName: _device?.name
    );

    launchManager.addLaunch(_launch);
  }

  Future<Launch> launch() async {
    FlutterTool flutter = _flutterSdk.sdk.flutterTool;

    _runner = _flutter(flutter, _args, cwd: project.path);
    _runner.execStreaming();
    _runner.onStdout.listen((String str) => _launch.pipeStdio(str));
    _runner.onStderr.listen((String str) => _launch.pipeStdio(str, error: true));
    _runner.onExit.then((code) => _launch.launchTerminated(code));

    return _launch;
  }

  Future _kill() {
    if (_runner == null) {
      _launch.launchTerminated(1);
      return new Future.value();
    } else {
      return new Future.delayed(new Duration(milliseconds: 250), () {
        _runner?.kill();
        _runner = null;
      });
    }
  }

  Device get _currentSelectedDevice => deviceManager.currentSelectedDevice;
}

ProcessRunner _flutter(FlutterTool flutter, List<String> args, {String cwd}) {
  return flutter.runRaw(args, cwd: cwd, startProcess: false);
}
