import 'dart:async';

import 'package:atom/node/process.dart';
import 'package:logging/logging.dart';

import '../launch/launch.dart';
import '../projects.dart';
import '../state.dart';
import 'dartino_util.dart';
import 'sdk/sdk.dart';

final Logger _logger = new Logger('atom.dartino_launch');

class DartinoLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new DartinoLaunchType());

  DartinoLaunch _lastLaunch;

  DartinoLaunchType() : super('dartino');

  bool canLaunch(String path, LaunchData data) {
    DartProject project = projectManager.getProjectFor(path);
    if (project == null || !project.isDartinoProject()) return false;

    return data.hasMain;
  }

  Future<Launch> performLaunch(
      LaunchManager manager, LaunchConfiguration configuration) async {
    String path = configuration.primaryResource;

    DartProject project = projectManager.getProjectFor(path);
    if (project == null || !project.isDartinoProject()) {
      throw "File not in a Dartino project.";
    }

    Sdk sdk = dartino.sdkFor(project.directory);
    if (sdk == null) {
      throw 'No SDK found for $project';
    }

    await _killLastLaunch();
    _lastLaunch = new DartinoLaunch(manager, this, configuration);
    manager.addLaunch(_lastLaunch);
    sdk.launch(_lastLaunch);
    return _lastLaunch;
  }

  String getDefaultConfigText() {
    //TODO(danrubel) add options for args, etc
    return '';
  }

  Future _killLastLaunch() async {
    if (_lastLaunch != null) {
      await _lastLaunch.kill();
      _lastLaunch = null;
    }
  }
}

class DartinoLaunch extends Launch {
  /// The current process runner or `null` if nothing running
  ProcessRunner runner;

  DartinoLaunch(LaunchManager manager, DartinoLaunchType launchType,
      LaunchConfiguration configuration)
      : super(manager, launchType, configuration,
            configuration.shortResourceName);

  bool canKill() => true;

  Future kill() async {
    if (runner != null) {
      await runner.kill();
      runner = null;
    }
  }

  /// Launch the specified external process and return a [Future]
  /// that completes with the external process's exit code.
  /// All output from the external process is piped to the console.
  /// The external process can be stopped by calling [kill].
  /// If this is not the last time [run] will be called for this launch
  /// (e.g. a compile before the launch) then set [isLast] `false`.
  Future<int> run(String command,
      {List<String> args,
      String cwd,
      String message,
      bool isLast: true,
      bool subtle: false,
      void onStdout(String msg)}) async {
    if (message != null) pipeStdio('$message\n');
    if (cwd != null) pipeStdio('\$ cd $cwd\n', highlight: true);
    pipeStdio('\$ $command ${args.join(' ')}\n', highlight: true);
    runner = new ProcessRunner(command, args: args, cwd: cwd);
    runner.onStdout.listen(onStdout ?? (str) => pipeStdio(str, subtle: subtle));
    runner.onStderr.listen((str) => pipeStdio('\n$str\n', error: true));
    var result;
    try {
      _logger.fine('launch: $command $args');
      result = await runner.execStreaming();
      _logger.fine('external process exited: $result');
    } catch (e, s) {
      _logger.info('external process exception', e, s);
      result = 183;
    }
    runner = null;
    if (result != 0) {
      pipeStdio('Process terminated with exitCode: $result\n', error: true);
    }
    if (result != 0 || isLast) exitCode.value = result;
    return result;
  }
}
