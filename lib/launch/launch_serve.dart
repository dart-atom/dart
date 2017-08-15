library atom.launch_serve;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';

import '../state.dart';
import 'launch.dart';

/// Pub serve launch.
class ServeLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new ServeLaunchType());

  ServeLaunchType() : super('serve');

  bool canLaunch(String path, LaunchData data) {
    return path.endsWith('pubspec.yaml');
  }

  bool get supportsChecked => false;

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    String cwd = configuration.cwd;
    List<String> args = configuration.argsAsList;

    String launchName = 'pub serve';

    // Determine the best cwd.
    if (cwd == null) {
      List<String> paths = atom.project.relativizePath(configuration.primaryResource);
      if (paths[0] != null) {
        cwd = paths[0];
        launchName = paths[1];
      }
    } else {
      launchName = fs.relativize(cwd, launchName);
    }

    List execArgs = ['serve']..addAll(args);

    ProcessRunner runner = sdkManager.sdk.execBin('pub', execArgs, cwd: cwd,
        startProcess: false);

    String description = (args == null || args.isEmpty) ? launchName : '${launchName} ${args.join(' ')}';
    Launch launch = new Launch(manager, this, configuration, launchName,
      killHandler: () => runner.kill(),
      cwd: cwd,
      title: description
    );
    manager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) => launch.pipeStdio(str));
    runner.onStderr.listen((str) => launch.pipeStdio(str, error: true));
    runner.onExit.then((code) => launch.launchTerminated(code));

    return new Future.value(launch);
  }

  String getDefaultConfigText() {
    return '''
# Additional args for pub serve
args:
  # Mode to run transformers in. (defaults to "debug")
  # --mode=debug
  # Use all default source directories.
  # --all
  # The JavaScript compiler to use to build the app. [dart2js, dartdevc, none]
  # --web-compiler=dartdevc
  # Defines an environment constant for dart2js.
  # --define
  # The hostname to listen on. (defaults to "localhost")
  # --hostname=localhost
  # The base port to listen on. (defaults to "8080")
  # --port=8080
  # Force the use of a polling filesystem watcher.
  # --[no-]force-poll
''';
  }
}
