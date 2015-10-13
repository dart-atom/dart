library atom.cli_launch;

import 'dart:async';
import 'dart:html' show WebSocket, MessageEvent;

import 'package:logging/logging.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../launch.dart';
import '../process.dart';
import '../projects.dart';
import '../sdk.dart';
import '../state.dart';

final Logger _logger = new Logger('atom.cli_launch');

const bool _debugDefault = true;
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

    return analysisServer.getExecutablesFor(project.path).where((path) {
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
    if (withDebug == null) withDebug = _debugDefault;
    if (!atom.config.getBoolValue('${pluginId}.enableDebugging')) {
      withDebug = false;
    }

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

    String desc = '[${cwd}] ${_args.join(' ')}\n';

    if (withDebug) {
      // TODO: Find an open port.
      //http://127.0.0.1:8181/
      // todo: --pause_isolates_on_start=true
      _args.insert(0, '--enable-vm-service=${_observePort}');
    }

    ProcessRunner runner = new ProcessRunner(
        sdk.dartVm.path,
        args: _args,
        cwd: cwd);

    Launch launch = new Launch(this, path, manager,
        killHandler: () => runner.kill());
    if (withDebug) launch.servicePort = _observePort;
    manager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) {
      // Observatory listening on http://127.0.0.1:16161
      if (str.startsWith('Observatory listening on ')) {
        _connectDebugger(launch, 'localhost', _observePort).catchError((e) {
          launch.pipeStderr('Error connecting debugger: ${e}\n');
        });
      } else {
        launch.pipeStdout(str);
      }
    });
    runner.onStderr.listen((str) => launch.pipeStderr(str));
    launch.pipeStdout(desc);
    runner.onExit.then((code) => launch.launchTerminated(code));

    return new Future.value(launch);
  }

  Future _connectDebugger(Launch launch, String host, int port) {
    String url = 'ws://${host}:${port}/ws';
    WebSocket ws = new WebSocket(url);

    Completer completer = new Completer();

    ws.onOpen.listen((_) {
      completer.complete();

      VmService service = new VmService(
        ws.onMessage.map((MessageEvent e) => e.data as String),
        (String message) => ws.send(message),
        log: new _Log()
      );
      _handleVMConnected(url, service);
    });

    ws.onError.listen((e) {
      if (!completer.isCompleted) completer.completeError(e);
    });

    return completer.future;
  }

  void _handleVMConnected(String url, VmService service) {
    _logger.fine('Connected to observatory on ${url}.');

    service.onSend.listen((str) => _logger.finer('==> ${str}'));
    service.onReceive.listen((str) => _logger.finer('<== ${str}'));

    service.getVersion().then((Version ver) {
      _logger.fine('Observatory version ${ver.major}.${ver.minor}.');
    });
  }
}

class _Log extends Log {
  void warning(String message) => _logger.warning(message);
  void severe(String message) => _logger.severe(message);
}
