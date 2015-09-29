library atom.cli_launch;

import 'dart:async';

import '../atom.dart';
import '../atom_utils.dart';
import '../launch.dart';
import '../process.dart';
import '../projects.dart';
import '../sdk.dart';
import '../state.dart';

class CliLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new CliLaunchType());

  CliLaunchType() : super('cli');

  bool canLaunch(String path) {
    // TODO: Fix this - this is a hack.
    if (!path.endsWith('.dart')) return false;

    File file = new File.fromPath(path);
    if (file.existsSync()) {
      String contents = file.readSync();
      return contents.contains('main(');
    }

    return false;
  }

  List<String> getLaunchablesFor(DartProject project) {
    // TODO:

    return [];
  }

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    Sdk sdk = sdkManager.sdk;

    if (sdk == null) new Future.error('No Dart SDK configured');

    String path = configuration.primaryResource;
    String cwd = configuration.cwd;
    List<String> args = configuration.argsAsList;

    DartProject project = projectManager.getProjectFor(path);

    // Determine the best cwd.
    if (cwd == null) {
      if (project == null) {
        List<String> paths = atom.project.relativizePath(path);
        if (paths[0] != null) {
          cwd = paths[0];
          path = paths[1];
        }
      } else {
        cwd = project.path;
        path = relativize(cwd, path);
      }
    } else {
      path = relativize(cwd, path);
    }

    List<String> _args = [path];
    if (args != null) _args.addAll(args);

    ProcessRunner runner = new ProcessRunner(
        sdk.dartVm.path,
        args: _args,
        cwd: cwd);

    Launch launch = new Launch(this, path, manager,
        killHandler: () => runner.kill());
    manager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) => launch.pipeStdout(str));
    runner.onStderr.listen((str) => launch.pipeStderr(str));

    launch.pipeStdout('[${cwd}] ${_args.join(' ')}\n');

    runner.onExit.then((code) => launch.launchTerminated(code));

    return new Future.value(launch);
  }
}
