import 'dart:async';

import 'package:atom/node/process.dart';
import 'package:atom_dartlang/debug/debugger.dart';
import 'package:atom_dartlang/debug/model.dart';
import 'package:logging/logging.dart';

import '../debug/observatory_debugger.dart';
import '../launch/launch.dart';
import '../projects.dart';
import '../state.dart';
import 'dartino.dart';
import 'sdk/dartino_sdk.dart';
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

  /// The Dartino SDK used to debug the app, or `null` if none.
  DartinoSdk sdk;

  DartinoLaunch(LaunchManager manager, DartinoLaunchType launchType,
      LaunchConfiguration configuration)
      : super(manager, launchType, configuration,
            configuration.shortResourceName);

  bool canKill() => true;

  Future kill() async {
    if (sdk != null) {
      await sdk.execBin('dartino', ['quit']).onExit;
      sdk = null;
    }
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
    if (result != 0 || isLast) launchTerminated(result, quiet: true);
    return result;
  }

  /// Start the debugging session and return `true` if successful.
  Future<bool> debug(DartinoSdk sdk, [String ttyPath]) async {
    String command = sdk.dartinoBinary;
    List<String> args = ['debug', 'serve', primaryResource];
    if (ttyPath != null) args.addAll(['on', 'tty', ttyPath]);

    pipeStdio('Starting debug session...\n');
    pipeStdio('\$ $command ${args.join(' ')}\n', highlight: true);
    runner = new ProcessRunner(command,
        args: args, cwd: launchConfiguration.projectPath);

    // Wait for the observatory port
    Completer<int> portCompleter = new Completer<int>();
    runner.onStdout.listen((str) {
      pipeStdio(str, subtle: true);
      if (str.startsWith('localhost:')) {
        try {
          portCompleter.complete(int.parse(str.substring(10).trim()));
        } catch (e) {
          pipeStdio('Failed to parse observatory port from "$str"\n',
              error: true);
          portCompleter.complete(null);
        }
      }
    });
    runner.onStderr.listen((str) => pipeStdio('\n$str\n', error: true));
    runner.execStreaming().then((int exitCode) {
      pipeStdio('debug session exit code is $exitCode\n', highlight: true);
      launchTerminated(exitCode, quiet: true);
    });
    this.sdk = sdk;
    int observatoryPort = await portCompleter.future;
    if (observatoryPort == null) {
      pipeStdio('Failed to determine observatory port\n', error: true);
      launchTerminated(1, quiet: true);
      return false;
    }

    // Connect to the observatory
    pipeStdio('Connecting observatory to application on device...\n');
    return await ObservatoryDebugger
        .connect(this, 'localhost', observatoryPort)
        .then((DebugConnection debugger) {
      servicePort.value = observatoryPort;
      return true;
    }).catchError((e, s) {
      pipeStdio(
          'Failed to connect to observatory on port $observatoryPort\n$e\n$s\n',
          error: true);
      launchTerminated(1, quiet: true);
      return false;
    });
  }
}
