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

  /// The last Flutter app run.
  String _lastRunProject;

  FlutterLaunchType() : super('flutter');

  bool canLaunch(String path) {
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return false;

    File skyTool = new File.fromPath(
        join(project.directory, 'packages', 'sky', 'sky_tool'));
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

    String sky_tool = join(project.directory, 'packages', 'sky', 'sky_tool');
    bool exists = new File.fromPath(sky_tool).existsSync();

    if (!exists) {
      return new Future.error("Unable to locate 'packages/sky/sky_tool'; "
          "did you import the 'sky' package into your project?");
    }

    // If this is the first time we've launched an app this session, ensure that
    // the sky server isn't already running (and potentially serving an older)
    // app. Also, if we're launching a different application.
    Future f = new Future.value();

    if (_lastRunProject != project.path) {
      _lastRunProject = project.path;
      f = _skyToolStop(project);
    }

    return f.then((_) => new _LaunchInstance(this, project).launch());
  }
}

class _LaunchInstance {
  final LaunchType launchType;
  final DartProject project;

  ProcessRunner _runner;

  _LaunchInstance(this.launchType, this.project);

  Future<Launch> launch() {
    // Chain together both 'sky_tool start' and 'sky_tool logs'.
    _runner = _skyTool(project, ['start']);

    Launch launch = new Launch(
        launchType,
        'lib${separator}main.dart',
        launchManager,
        killHandler: () => _runner.kill());
    launch.servicePort = 8181;
    launchManager.addLaunch(launch);

    _runner.execStreaming();
    _runner.onStdout.listen((str) => launch.pipeStdout(str));
    _runner.onStderr.listen((str) => launch.pipeStderr(str));

    launch.pipeStdout('[${_runner.cwd}] ${_runner.getDescription()}\n');

    return _runner.onExit.then((code) {
      _runner = null;

      if (code == 0) {
        // Chain 'sky_tool logs'.
        _runner = _skyTool(project, ['logs', '--clear']);
        _runner.execStreaming();
        _runner.onStdout.listen((str) => launch.pipeStdout(str));
        _runner.onStderr.listen((str) => launch.pipeStderr(str));

        // Don't return the future here.
        _runner.onExit.then((code) => launch.launchTerminated(code));
      } else {
        launch.launchTerminated(code);
      }
    });
  }
}

ProcessRunner _skyTool(DartProject project, List<String> args) {
  final String skyToolPath = 'packages${separator}sky${separator}sky_tool';

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
