library atom.shell_launch;

import 'dart:async';

import '../launch.dart';
import '../process.dart';

class ShellLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new ShellLaunchType());

  ShellLaunchType() : super('shell');

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    // TODO: primary resource, cwd, args
    String script = configuration.primaryResource;
    String cwd = configuration.cwd;
    List<String> args = configuration.args;

    // TODO: determine the best cwd

    ProcessRunner runner = new ProcessRunner(script, args: args, cwd: cwd);

    Launch launch = new Launch(this, script, manager,
        killHandler: () => runner.kill());
    manager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) => launch.pipeStdout(str));
    runner.onStderr.listen((str) => launch.pipeStderr(str));

    if (runner.cwd != null) {
      launch.pipeStdout('[${runner.cwd}] ${runner.getDescription()}\n');
    } else {
      launch.pipeStdout('${runner.getDescription()}\n');
    }

    runner.onExit.then((code) => launch.launchTerminated(code));

    return new Future.value(launch);
  }
}
