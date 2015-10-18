library atom.flutter.launch_flutter;

import 'dart:async';

import '../atom.dart';
import '../atom_utils.dart';
import '../impl/pub.dart';
import '../launch/launch.dart';
import '../process.dart';
import '../projects.dart';
import '../state.dart';

const String _toolName = 'flutter';

class FlutterLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new FlutterLaunchType());

  _LaunchInstance _lastLaunch;

  FlutterLaunchType() : super('flutter');

  bool canLaunch(String path) {
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return false;

    PubAppLocal flutter = new PubApp.local(_toolName, project.path);
    if (!flutter.isInstalledSync()) return false;

    String relPath = relativize(project.path, path);
    return relPath == 'lib${separator}main.dart';
  }

  List<String> getLaunchablesFor(DartProject project) {
    File file = project.directory.getFile('lib${separator}main.dart');
    return file.existsSync() ? [file.path] : [];
  }

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    String path = configuration.primaryResource;
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return new Future.error("File not in a Dart project.");

    PubAppLocal flutter = new PubApp.local(_toolName, project.path);
    bool exists = flutter.isInstalledSync();

    if (!exists) {
      return new Future.error("Unable to locate the '${_toolName}' package; "
          "did you import it into your project?");
    }

    return _killLastLaunch().then((_) {
      _lastLaunch = new _LaunchInstance(project, configuration, this);
      return _lastLaunch.launch();
    });
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

  _LaunchInstance(this.project, LaunchConfiguration configuration, LaunchType launchType) {
    _launch = new Launch(
        launchManager,
        launchType,
        configuration,
        'lib${separator}main.dart',
        killHandler: _kill);
    // TODO: Only set this value on successful connect.
    _launch.servicePort.value = 8181;
    launchManager.addLaunch(_launch);
    _launch.pipeStdio('[${project.path}] pub run ${_toolName} start\n', highlight: true);
  }

  Future<Launch> launch() async {
    PubAppLocal flutter = new PubApp.local(_toolName, project.path);

    // Ensure that the sky server isn't already running and potentially serving
    // an older (or different) app.
    _runner = _flutter(flutter, ['stop']);
    _runner.execStreaming();
    _runner.onStdout.listen((str) => _launch.pipeStdio(str));
    _runner.onStderr.listen((str) => _launch.pipeStdio(str, error: true));

    Future f = _runner.onExit.timeout(new Duration(seconds: 4), onTimeout: () => 0);
    await f;

    // Chain together both 'flutter start' and 'flutter logs'.
    // TODO: Add a user option for `--checked`.
    _runner = _flutter(flutter, ['start']); //, '--poke']);
    _runner.execStreaming();
    _runner.onStdout.listen((str) => _launch.pipeStdio(str));
    _runner.onStderr.listen((str) => _launch.pipeStdio(str, error: true));

    int code = await _runner.onExit;
    if (code == 0) {
      // Chain 'flutter logs'.
      _runner = _flutter(flutter, ['logs', '--clear']);
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
      return _runner.kill();
    }
  }
}

ProcessRunner _flutter(PubAppLocal flutter, List<String> args) {
  return flutter.runRaw(args, startProcess: false);
}

// Future<bool> hasFswatchInstalled() {
//   return exec('fswatch', ['--version']).then((_) => true).catchError((_) => false);
// }
