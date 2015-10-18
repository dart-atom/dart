library atom.launch_cli;

import 'dart:async';
import 'dart:html' show WebSocket, MessageEvent;

import 'package:logging/logging.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../debug/breakpoints.dart';
import '../debug/debugger.dart';
import '../debug/observatory_debugger.dart';
import '../process.dart';
import '../projects.dart';
import '../sdk.dart';
import '../state.dart';
import '../utils.dart';
import 'launch.dart';

final Logger _logger = new Logger('atom.launch_cli');

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
      _args.insert(0, '--pause_isolates_on_start=true');
      _args.insert(0, '--enable-vm-service=${_observePort}');
    }

    ProcessRunner runner = new ProcessRunner(
        sdk.dartVm.path,
        args: _args,
        cwd: cwd);

    Launch launch = new Launch(manager, this, configuration, path,
        killHandler: () => runner.kill());
    if (withDebug) launch.servicePort = _observePort;
    manager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) {
      // Observatory listening on http://127.0.0.1:16161
      if (str.startsWith('Observatory listening on ')) {
        _connectDebugger(launch, 'localhost', _observePort).catchError((e) {
          launch.pipeStdio('Error connecting debugger: ${e}\n', error: true);
        });
      } else {
        launch.pipeStdio(str);
      }
    });
    runner.onStderr.listen((str) => launch.pipeStdio(str, error: true));
    launch.pipeStdio(desc, highlight: true);
    runner.onExit.then((code) => launch.launchTerminated(code));

    return new Future.value(launch);
  }

  Future _connectDebugger(Launch launch, String host, int port) {
    String url = 'ws://${host}:${port}/ws';
    WebSocket ws = new WebSocket(url);

    Completer connectedCompleter = new Completer();
    Completer finishedCompleter = new Completer();

    ws.onOpen.listen((_) {
      connectedCompleter.complete();

      VmService service = new VmService(
        ws.onMessage.map((MessageEvent e) => e.data as String),
        (String message) => ws.send(message),
        log: new ObserveLog(_logger)
      );
      _handleVMConnected(launch, url, service, finishedCompleter, isolatesPaused: true);
    });

    ws.onError.listen((e) {
      if (!connectedCompleter.isCompleted) connectedCompleter.completeError(e);
    });

    ws.onClose.listen((_) => finishedCompleter.complete());

    return connectedCompleter.future;
  }

  void _handleVMConnected(Launch launch, String url, VmService service, Completer completer, {
    bool isolatesPaused: true
  }) {
    _logger.fine('Connected to observatory on ${url}.');

    launch.addDebugConnection(new _ObservatoryDebugConnection(launch, service, completer));
  }
}

class _ObservatoryDebugConnection extends DebugConnection {
  final VmService service;
  final Completer completer;

  IsolateRef _currentIsolate;
  StreamSubscriptions subs = new StreamSubscriptions();
  UriResolver uriResolver;

  bool isSuspended = true;
  StreamController<bool> _suspendController = new StreamController.broadcast();

  _ObservatoryDebugConnection(Launch launch, this.service, this.completer) : super(launch) {
    uriResolver = new UriResolver(launch.launchConfiguration.primaryResource);
    _init();
    completer.future.whenComplete(() => dispose());
  }

  bool get isAlive => !completer.isCompleted;

  Stream<bool> get onSuspendChanged => _suspendController.stream;

  pause() => service.pause(_currentIsolate.id);
  Future resume() => service.resume(_currentIsolate.id);

  // TODO: only on suspend.
  stepIn() => service.resume(_currentIsolate.id, step: StepOption.Into);
  stepOver() => service.resume(_currentIsolate.id, step: StepOption.Over);
  stepOut() => service.resume(_currentIsolate.id, step: StepOption.Out);

  terminate() => launch.kill();

  Future get onTerminated => completer.future;

  void _init() {
    // TODO: init breakpoints as isolates are created
    // TODO: resume each isolate after creation

    service.onSend.listen((str) => _logger.fine('==> ${str}'));
    service.onReceive.listen((str) => _logger.fine('<== ${str}'));

    service.getVersion().then((Version ver) {
      _logger.fine('Observatory version ${ver.major}.${ver.minor}.');
    });

    service.streamListen('Isolate');
    service.streamListen('Debug');
    service.streamListen('Stdout');
    service.streamListen('Stderr');

    service.onIsolateEvent.listen(_handleIsolateEvent);
    service.onDebugEvent.listen(_handleDebugEvent);
    //service.onStdoutEvent.listen((Event e) => _stdio(e, 'stdout'));
    //service.onStderrEvent.listen((Event e) => _stdio(e, 'stderr'));
  }

  // void _stdio(Event e, String prefix) {
  //   print('[stdio: ${decodeBase64(e.bytes).trim()}]');
  // }

  void _handleIsolateEvent(Event e) {
    // TODO: isolate handler

    launch.pipeStdio('${e}\n', subtle: true);

    // IsolateStart, IsolateRunnable, IsolateExit, IsolateUpdate
    if (e.kind == EventKind.IsolateRunnable) {
      _currentIsolate = e.isolate;

      Map<AtomBreakpoint, Breakpoint> _bps = {};

      // TODO: Run these in parallel.
      Future.forEach(breakpointManager.breakpoints, (AtomBreakpoint bp) {
        Future f = service.addBreakpointWithScriptUri(
          _currentIsolate.id, bp.asUrl, bp.line, column: bp.column);
        return f.then((Breakpoint vmBreakpoint) {
          _bps[bp] = vmBreakpoint;
          print(vmBreakpoint);
        }).catchError((e) {
          // ignore
        });
      }).then((_) {
        return service.setExceptionPauseMode(
          _currentIsolate.id, ExceptionPauseMode.Unhandled);
      }).then((_) {
        return resume();
      });

      subs.add(breakpointManager.onAdd.listen((bp) {
        Future f = service.addBreakpointWithScriptUri(
          _currentIsolate.id, bp.asUrl, bp.line, column: bp.column);
        f.then((Breakpoint vmBreakpoint) {
          _bps[bp] = vmBreakpoint;
        }).catchError((e) {
          // ignore
        });
      }));

      subs.add(breakpointManager.onRemove.listen((bp) {
        Breakpoint vmBreakpoint = _bps[bp];
        if (vmBreakpoint != null) {
          service.removeBreakpoint(_currentIsolate.id, vmBreakpoint.id);
        }
      }));
    } else if (e.kind == EventKind.IsolateExit) {
      _currentIsolate = null;
    }
  }

  void _handleDebugEvent(Event e) {
    IsolateRef isolate = e.isolate;
    // bool paused = e.kind == EventKind.PauseBreakpoint ||
    //     e.kind == EventKind.PauseInterrupted || e.kind == EventKind.PauseException;

    if (e.kind == EventKind.Resume) {
      _suspend(false);
    } else if (e.kind == EventKind.PauseBreakpoint || e.kind == EventKind.PauseInterrupted ||
        e.kind == EventKind.PauseException) {
      _suspend(true);
    }

    if (e.kind == EventKind.Resume || e.kind == EventKind.IsolateExit) {
      // TODO: isolate is resumed
    }

    if (e.kind != EventKind.Resume) {
      if (e.topFrame != null) {
        launch.pipeStdio('[${isolate.name}] ${printFunctionName(e.topFrame.function)}', subtle: true);
        ScriptRef scriptRef = e.topFrame.location.script;

        _resolveScript(isolate, scriptRef).then((Script script) {
          int tokenPos = e.topFrame.location.tokenPos;
          Point pos = calcPos(script, tokenPos);
          String uri = script.uri;

          if (pos != null) {
            launch.pipeStdio(' [${uri}, ${pos.row}]\n', subtle: true);

            uriResolver.resolveToPath(uri).then((String path) {
              if (statSync(path).isFile()) {
                editorManager.jumpToLocation(path, pos.row - 1, pos.column - 1).then(
                    (TextEditor editor) {
                  // TODO: update the execution location markers

                });
              } else {
                atom.notifications.addWarning("Cannot file file '${path}'.");
              }
            }).catchError((e) {
              atom.notifications.addWarning(
                  "Unable to resolve '${uri}' (${pos.row}:${pos.column}).");
            });
          } else {
            launch.pipeStdio(' [${uri}]\n', subtle: true);
          }
        });
      }
    }
  }

  Map<String, Script> _scripts = {};

  Future<Script> _resolveScript(IsolateRef isolate, ScriptRef scriptRef) {
    String id = scriptRef.id;

    if (_scripts[id] != null) return new Future.value(_scripts[id]);

    return service.getObject(isolate.id, id).then((result) {
      if (result is Script) {
        _scripts[id] = result;
        return result;
      }
      throw result;
    });
  }

  void _suspend(bool value) {
    if (value != isSuspended) {
      isSuspended = value;
      _suspendController.add(value);
    }
  }

  void dispose() {
    subs.cancel();
    if (isAlive) terminate();
    uriResolver.dispose();
  }
}
