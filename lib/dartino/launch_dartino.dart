import 'dart:async';

import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:logging/logging.dart';

import '../atom.dart';
import '../launch/launch.dart';
import '../projects.dart';
import '../state.dart';

final Logger _logger = new Logger('atom.dartino_launch');

class DartinoLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new DartinoLaunchType());

  DartinoLaunch _lastLaunch;

  DartinoLaunchType() : super('dartino');

  bool canLaunch(String path) {
    DartProject project = projectManager.getProjectFor(path);
    if (project == null || !project.isDartinoProject()) return false;
    if (!analysisServer.isExecutable(path)) return false;
    return true;
  }

  List<String> getLaunchablesFor(DartProject project) {
    if (project == null || !project.isDartinoProject()) return [];
    var files = <String>[];
    visit(Directory dir) {
      for (Entry entry in dir.getEntriesSync()) {
        if (entry.isDirectory()) {
          visit(entry);
          continue;
        }
        var path = entry.getPath();
        if (path != null && path.endsWith('dart')) files.add(path);
      }
    }
    visit(project.directory);
    return files;
    //TODO(danrubel) add Dartino launch support to analysis server
    // return analysisServer
    //     .getExecutablesFor(project.path)
    //     .where((String path) => path.endsWith('dart'))
    //     .toList();
  }

  Future<Launch> performLaunch(
      LaunchManager manager, LaunchConfiguration configuration) async {
    String path = configuration.primaryResource;

    DartProject project = projectManager.getProjectFor(path);
    if (project == null || !project.isDartinoProject()) {
      throw "File not in a Dartino project.";
    }

    // Sdk sdk = dartino.sdkFor(project.directory);
    // if (sdk == null) {
    //   throw 'No SDK found for $project';
    // }

    await _killLastLaunch();
    _lastLaunch = new DartinoLaunch(manager, this, configuration);
    manager.addLaunch(_lastLaunch);
    // TODO (danrubel) to be implemented
    // sdk.launch(_lastLaunch);
    atom.notifications.addError('Not implemented yet');
    return _lastLaunch;
  }

  String getDefaultConfigText() {
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
  Future<int> run(String command,
      {List args, String cwd, String message, bool subtle: false}) async {
    if (message != null) pipeStdio('$message\n');
    runner = new ProcessRunner(command, args: args, cwd: cwd);
    runner.onStdout.listen((str) {
      str = str.replaceAll('Download', '\nDownload');
      pipeStdio(str, subtle: subtle);
    });
    runner.onStderr.listen((str) => pipeStdio('\n$str\n', error: true));
    var exitCode = await runner.execStreaming();
    runner = null;
    return exitCode;
  }
}
