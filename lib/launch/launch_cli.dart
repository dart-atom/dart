library atom.launch_cli;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:atom_dartlang/dartino/dartino.dart' show dartino;
import 'package:logging/logging.dart';

import '../debug/observatory_debugger.dart' show ObservatoryDebugger;
import '../projects.dart';
import '../sdk.dart';
import '../state.dart';
import 'launch.dart';

final Logger _logger = new Logger('atom.launch_cli');

final String _observatoryPrefix = 'Observatory listening on ';

class CliLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new CliLaunchType());

  CliLaunchType() : super('cli');

  bool canLaunch(String path, LaunchData data) {
    if (!path.endsWith('.dart')) return false;

    DartProject project = projectManager.getProjectFor(path);

    if (project == null) {
      return data.hasMain;
    } else {
      // Check that the file is not in lib/.
      String relativePath = fs.relativize(project.path, path);
      if (relativePath.startsWith('lib${fs.separator}')) return false;

      if (dartino.isProject(project.directory.path)) return false;
      return data.hasMain;
    }
  }

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    Sdk sdk = sdkManager.sdk;

    if (sdk == null) new Future.error('No Dart SDK configured');

    bool withDebug = configuration.debug;
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
        path = fs.relativize(cwd, path);
      }
    } else {
      path = fs.relativize(cwd, path);
    }

    List<String> _args = [];

    int observatoryPort;

    if (withDebug) {
      observatoryPort = getOpenPort();
      _args.add('--enable-vm-service:${observatoryPort}');
      _args.add('--pause_isolates_on_start=true');
    }

    if (configuration.checked) _args.add('--checked');

    _args.add(path);
    if (args != null) _args.addAll(args);

    String description = (args == null || args.isEmpty) ? path : '${path} ${args.join(' ')}';

    // Run in `underShell` to capture environment variables on the mac.
    ProcessRunner runner = new ProcessRunner.underShell(
      sdk.dartVm.path,
      args: _args,
      cwd: cwd
    );

    Launch launch = new _CliLaunch(manager, this, configuration, path,
      killHandler: () => runner.kill(),
      cwd: cwd,
      project: project,
      title: description
    );
    manager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) {
      // "Observatory listening on http://127.0.0.1:xxx\n"
      if (str.startsWith(_observatoryPrefix)) {
        // str is 'http://127.0.0.1:xxx'.
        str = str.substring(_observatoryPrefix.length).trim();

        launch.servicePort.value = observatoryPort;

        ObservatoryDebugger.connect(launch, 'localhost', observatoryPort).catchError((e) {
          launch.pipeStdio(
            'Unable to connect to the observatory (port ${observatoryPort}).\n',
            error: true
          );
        });
      } else {
        launch.pipeStdio(str);
      }
    });
    runner.onStderr.listen((str) => launch.pipeStdio(str, error: true));
    runner.onExit.then((int code) => launch.launchTerminated(code));

    return new Future.value(launch);
  }

  String getDefaultConfigText() {
    return '''
# Additional args for the application.
args:
# The working directory to use for the launch.
cwd:
# Enable or disable checked mode.
checked: true
# Enable or disable debugging.
debug: true
''';
  }
}

// TODO: Move more launching functionality into this class.
class _CliLaunch extends Launch {
  CachingServerResolver _resolver;

  _CliLaunch(
    LaunchManager manager,
    LaunchType launchType,
    LaunchConfiguration launchConfiguration,
    String name,
    { Function killHandler, String cwd, DartProject project, String title }
  ) : super(
    manager,
    launchType,
    launchConfiguration,
    name,
    killHandler: killHandler,
    cwd: cwd,
    title: title
  ) {
    _resolver = new CachingServerResolver(
      cwd: project?.path,
      server: analysisServer
    );

    exitCode.onChanged.first.then((_) => _resolver.dispose());
  }

  Future<String> resolve(String url) => _resolver.resolve(url);
}
