library atom.launch_serve;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';

import '../projects.dart';
import '../state.dart';
import 'launch.dart';

const singletonBoolParameters = const ['all', 'force-poll', 'no-force-poll'];

/// Pub serve launch.
class ServeLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new ServeLaunchType());

  ServeLaunchType() : super('serve');

  bool canLaunch(String path, LaunchData data) {
    return path.endsWith('pubspec.yaml');
  }

  bool get supportsChecked => false;

  Future<Launch> performLaunch(
      LaunchManager manager, LaunchConfiguration configuration) {
    String cwd = configuration.cwd;
    var args = configuration.typeArgs['args'] ?? {};

    String launchName = 'pub serve';

    // Determine the best cwd.
    if (cwd == null) {
      List<String> paths =
          atom.project.relativizePath(configuration.primaryResource);
      if (paths[0] != null) {
        cwd = paths[0];
        launchName = paths[1];
      }
    } else {
      launchName = fs.relativize(cwd, launchName);
    }

    List execArgs = ['serve'];
    if (args is Map) {
      args.forEach((k, v) {
        if (singletonBoolParameters.contains(k)) {
          if (v) execArgs.add('--$k');
        } else {
          execArgs.add('--$k=$v');
        }
      });
    }
    ProcessRunner runner =
        sdkManager.sdk.execBin('pub', execArgs, cwd: cwd, startProcess: false);

    String root =
        'http://${args['hostname'] ?? 'localhost'}:${args['port'] ?? 'port'}';
    Launch launch = new ServeLaunch(
        manager, this, configuration, launchName, root,
        killHandler: () => runner.kill(), cwd: cwd, title: launchName);
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
  #mode: debug
  # Use all default source directories.
  #all: true
  # The JavaScript compiler to use to build the app. [dart2js, dartdevc, none]
  #web-compiler: dartdevc
  # Defines an environment constant for dart2js.
  #define: variable=value[,variable=value]
  # The hostname to listen on. (defaults to "localhost")
  #hostname: localhost
  # The base port to listen on. (defaults to "8080")
  port: 8084
  # Force the use of a polling filesystem watcher.
  #force-poll: true
  #no-force-poll: true
''';
  }
}

class ServeLaunch extends Launch {
  String _root;
  String get root => _root;

  ServeLaunch(LaunchManager manager, LaunchType launchType,
      LaunchConfiguration launchConfiguration, String name, String root,
      {Function killHandler, String cwd, DartProject project, String title})
      : _root = root,
        super(manager, launchType, launchConfiguration, name,
            killHandler: killHandler, cwd: cwd, title: title);
}
