library atom.flutter_launch;

import 'dart:async';

import '../atom.dart';
import '../atom_utils.dart';
import '../launch.dart';
import '../process.dart';
import '../projects.dart';
import '../state.dart';

class FlutterLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new FlutterLaunchType());

  _LaunchInstance _lastLaunch;

  FlutterLaunchType() : super('flutter');

  bool canLaunch(String path) {
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return false;

    File skyTool = new File.fromPath(
        join(project.directory, 'packages', 'flutter', 'sky_tool'));
    if (!skyTool.existsSync()) return false;

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

    String sky_tool = join(project.directory, 'packages', 'flutter', 'sky_tool');
    bool exists = new File.fromPath(sky_tool).existsSync();

    if (!exists) {
      return new Future.error("Unable to locate 'packages/flutter/sky_tool'; "
          "did you import the 'sky' package into your project?");
    }

    // Ensure that the sky server isn't already running and potentially serving
    // an older (or different) app.
    return _skyToolStop(project).then((_) {
      if (_lastLaunch == null) return null;

      Launch launch = _lastLaunch._launch;
      return launch.isTerminated ? null : launch.kill();
    }).then((_) {
      _lastLaunch = new _LaunchInstance(project, this);
      return _lastLaunch.launch();
    });
  }
}

class _LaunchInstance {
  final DartProject project;

  Launch _launch;
  ProcessRunner _runner;

  _LaunchInstance(this.project, LaunchType launchType) {
    _launch = new Launch(
        launchType,
        'lib${separator}main.dart',
        launchManager,
        killHandler: _kill);
    _launch.servicePort = 8181;
  }

  Future<Launch> launch() {
    // Chain together both 'sky_tool start' and 'sky_tool logs'.
    _runner = _skyTool(project, ['start']); //, '--poke']);

    launchManager.addLaunch(_launch);

    _runner.execStreaming();
    _runner.onStdout.listen((str) => _launch.pipeStdio(str));
    _runner.onStderr.listen((str) => _launch.pipeStdio(str, error: true));

    _launch.pipeStdio('[${_runner.cwd}] ${_runner.getDescription()}\n', highlight: true);

    // TODO: Hack - `sky_tool start` is not terminating when launched from Atom.
    Future f = _runner.onExit.timeout(new Duration(seconds: 2), onTimeout: () => 0);
    return f.then((code) {
      _runner = null;

      if (code == 0) {
        // Chain 'sky_tool logs'.
        _runner = _skyTool(project, ['logs', '--clear']);
        _runner.execStreaming();
        _runner.onStdout.listen((str) => _launch.pipeStdio(str));
        _runner.onStderr.listen((str) => _launch.pipeStdio(str, error: true));

        // Don't return the future here.
        _runner.onExit.then((code) => _launch.launchTerminated(code));
      } else {
        _launch.launchTerminated(code);
      }
    });
  }

  Future _kill() => _runner.kill();
}

ProcessRunner _skyTool(DartProject project, List<String> args) {
  final String skyToolPath = 'packages${separator}flutter${separator}sky_tool';

  if (isMac) {
    // On the mac, run under bash.
    return new ProcessRunner('/bin/bash',
        args: ['-l', '-c', '${skyToolPath} ${args.join(' ')}'], cwd: project.path);
  } else {
    args.insert(0, skyToolPath);
    return new ProcessRunner('python', args: args, cwd: project.path);
  }
}

/// Run `sky_tool stop` and ignore any error conditions that may occur.
Future _skyToolStop(DartProject project) {
  return _skyTool(project, ['stop']).execSimple();
}

// Future<bool> hasFswatchInstalled() {
//   return exec('fswatch', ['--version']).then((_) => true).catchError((_) => false);
// }
