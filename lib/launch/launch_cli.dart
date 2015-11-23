library atom.launch_cli;

import 'dart:async';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../debug/observatory_debugger.dart' show ObservatoryDebugger;
import '../process.dart';
import '../projects.dart';
import '../sdk.dart';
import '../state.dart';
import 'launch.dart';

final Logger _logger = new Logger('atom.launch_cli');

const int _observePort = 16161;

class CliLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new CliLaunchType());

  CliLaunchType() : super('cli');

  bool canLaunch(String path) {
    if (!path.endsWith('.dart')) return false;

    DartProject project = projectManager.getProjectFor(path);

    if (project == null) {
      File file = new File.fromPath(path);
      if (!file.existsSync()) return false;

      String contents = file.readSync();
      return contents.contains('main(');
    } else {
      // Check that the file is not in lib/.
      String relativePath = relativize(project.path, path);
      if (relativePath.startsWith('lib${separator}')) return false;

      return analysisServer.isExecutable(path);
    }
  }

  List<String> getLaunchablesFor(DartProject project) {
    final String libSuffix = 'lib${separator}';

    return analysisServer.getExecutablesFor(project.path).where((String path) {
      // Check that the file is not in lib/.
      String relativePath = relativize(project.path, path);
      if (relativePath.startsWith(libSuffix)) return false;
      return true;
    }).toList();
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
        path = relativize(cwd, path);
      }
    } else {
      path = relativize(cwd, path);
    }

    List<String> _args = [];

    if (withDebug) {
      // TODO: Find an open port.
      //http://127.0.0.1:8181/
      // todo: --pause_isolates_on_start=true
      _args.add('--pause_isolates_on_start=true');
      _args.add('--enable-vm-service=${_observePort}');
    }

    if (configuration.checked) _args.add('--checked');

    _args.add(path);
    if (args != null) _args.addAll(args);

    String description = '${path} ${args == null ? '' : args.join(' ')}';

    ProcessRunner runner = new ProcessRunner(
      sdk.dartVm.path,
      args: _args,
      cwd: cwd);

    Launch launch = new _CliLaunch(manager, this, configuration, path,
      killHandler: () => runner.kill(),
      cwd: cwd,
      project: project,
      title: description
    );
    if (withDebug) launch.servicePort.value = _observePort;
    manager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) {
      // Observatory listening on http://127.0.0.1:16161
      if (str.startsWith('Observatory listening on ')) {
        Future f = ObservatoryDebugger.connect(
            launch, 'localhost', _observePort, isolatesStartPaused: true);
        f.catchError((e) {
          launch.pipeStdio(
              'Unable to connect to the observatory (port ${_observePort}).\n',
              error: true);
        });
      } else {
        launch.pipeStdio(str);
      }
    });
    runner.onStderr.listen((str) => launch.pipeStdio(str, error: true));
    runner.onExit.then((code) => launch.launchTerminated(code));

    return new Future.value(launch);
  }

  String getDefaultConfigText() {
    return 'args: \nchecked: true\n';
  }
}

// TODO: Move more launching functionality into this class
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
