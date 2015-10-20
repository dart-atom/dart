library atom.observatory_debugger;

import 'dart:async';
import 'dart:html' show WebSocket, MessageEvent;

import 'package:logging/logging.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import '../atom.dart';
import '../launch/launch.dart';
import '../state.dart';
import '../utils.dart';
import 'breakpoints.dart';
import 'debugger.dart';

final Logger _logger = new Logger('atom.observatory');

class ObservatoryDebugger {
  static Future<DebugConnection> connect(Launch launch, String host, int port, {
    bool isolatesStartPaused: false,
    UriTranslator uriTranslator
  }) {
    String url = 'ws://${host}:${port}/ws';
    WebSocket ws = new WebSocket(url);

    Completer connectedCompleter = new Completer();
    Completer finishedCompleter = new Completer();

    ws.onOpen.listen((_) {
      connectedCompleter.complete();

      VmService service = new VmService(
        ws.onMessage.map((MessageEvent e) => e.data as String),
        (String message) => ws.send(message),
        log: new ObservatoryLog(_logger)
      );

      _logger.info('Connected to observatory on ${url}.');
      launch.addDebugConnection(new _ObservatoryDebugConnection(
          launch,
          service,
          finishedCompleter,
          isolatesStartPaused: isolatesStartPaused,
          uriTranslator: uriTranslator));
    });

    ws.onError.listen((e) {
      _logger.fine('Unable to connect to observatory, port ${port}', e);
      if (!connectedCompleter.isCompleted) connectedCompleter.completeError(e);
    });

    ws.onClose.listen((_) => finishedCompleter.complete());

    return connectedCompleter.future;
  }
}

class _ObservatoryDebugConnection extends DebugConnection {
  final VmService service;
  final Completer completer;
  final bool pipeStdio;
  final bool isolatesStartPaused;

  IsolateRef _currentIsolate;
  StreamSubscriptions subs = new StreamSubscriptions();
  UriResolver uriResolver;

  bool stdoutSupported = true;
  bool stderrSupported = true;

  bool isSuspended = true;
  StreamController<bool> _suspendController = new StreamController.broadcast();

  _ObservatoryDebugConnection(Launch launch, this.service, this.completer, {
    this.pipeStdio: false,
    this.isolatesStartPaused: false,
    UriTranslator uriTranslator
  }) : super(launch) {
    String root = launch.primaryResource;
    if (launch.project != null) root = launch.project.path;
    uriResolver = new UriResolver(root,
        translator: uriTranslator,
        selfRefName: launch.project?.getSelfRefName());
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
    service.onSend.listen((str) => _logger.fine('==> ${str}'));
    service.onReceive.listen((str) => _logger.fine('<== ${str}'));

    // TODO: Recommended boot-up sequence (done synchronously):
    // 1) getVersion.
    // 2) streamListen(Debug)
    // 3) streamListen(Isolate)
    // 4) getVM()
    // 5) getIsolate(id)

    service.getVersion().then((Version ver) {
      _logger.fine('Observatory version ${ver.major}.${ver.minor}.');
    });

    service.onIsolateEvent.listen(_handleIsolateEvent);
    service.streamListen('Isolate');

    service.onDebugEvent.listen(_handleDebugEvent);
    service.streamListen('Debug');

    if (pipeStdio) {
      service.onStdoutEvent.listen((Event e) {
        launch.pipeStdio(decodeBase64(e.bytes));
      });
      service.streamListen('Stdout').catchError((_) => stdoutSupported = false);

      service.onStderrEvent.listen((Event e) {
        launch.pipeStdio(decodeBase64(e.bytes), error: true);
      });
      service.streamListen('Stderr').catchError((_) => stderrSupported = false);
    }

    service.getVM().then((VM vm) {
      _logger.info('Connected to ${vm.architectureBits}/${vm.targetCPU}/'
          '${vm.hostCPU}/${vm.version}');
      if (!isolatesStartPaused && vm.isolates.isNotEmpty) {
        _currentIsolate = vm.isolates.first;
        _installInto(_currentIsolate).then((_) {
          _suspend(false);
        });

        // service.getIsolate(_currentIsolate.id).then((Isolate i) {
        //   print('root lib = ${i.rootLib}');
        // });
      } else if (isolatesStartPaused && vm.isolates.isNotEmpty) {
        _currentIsolate = vm.isolates.first;
        _installInto(_currentIsolate).then((_) {
          service.resume(_currentIsolate.id);
        });
      }
    });
  }

  Future _installInto(IsolateRef isolate) {
    Map<AtomBreakpoint, Breakpoint> _bps = {};

    subs.add(breakpointManager.onAdd.listen((bp) {
      uriResolver.resolvePathToUri(bp.path).then((List<String> uris) {
        // TODO: Use both returned values.
        return service.addBreakpointWithScriptUri(
            _currentIsolate.id, uris.first, bp.line, column: bp.column);
      }).then((Breakpoint vmBreakpoint) {
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

    // TODO: Run these in parallel.
    // TODO: Need to handle self-references and editor breakpoints multiplexed
    // over several VM breakpoints.
    return Future.forEach(breakpointManager.breakpoints, (AtomBreakpoint bp) {
      return uriResolver.resolvePathToUri(bp.path).then((List<String> uris) {
        // TODO: Use both returned values.
        return service.addBreakpointWithScriptUri(
            _currentIsolate.id, uris.first, bp.line, column: bp.column);
      }).then((Breakpoint vmBreakpoint) {
        _bps[bp] = vmBreakpoint;
      }).catchError((e) {
        // ignore
      });
    }).then((_) {
      return service.setExceptionPauseMode(
        _currentIsolate.id, ExceptionPauseMode.Unhandled);
    });
  }

  void _handleIsolateEvent(Event e) {
    // TODO: isolate handler

    launch.pipeStdio('${e}\n', subtle: true);

    // IsolateStart, IsolateRunnable, IsolateExit, IsolateUpdate
    if (e.kind == EventKind.IsolateRunnable) {
      // TODO: Don't re-init if it is already inited.
      _currentIsolate = e.isolate;
      _installInto(_currentIsolate).then((_) {
        if (isolatesStartPaused) resume();
      });
    } else if (e.kind == EventKind.IsolateExit) {
      _currentIsolate = null;
    }
  }

  void _handleDebugEvent(Event e) {
    IsolateRef isolate = e.isolate;

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
          Point pos = _calcPos(script, tokenPos);
          String uri = script.uri;

          if (pos != null) {
            launch.pipeStdio(' [${uri}, ${pos.row}]\n', subtle: true);

            uriResolver.resolveUriToPath(uri).then((String path) {
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

String printFunctionName(FuncRef ref, {bool terse: false}) {
  String name = terse ? ref.name : '${ref.name}()';

  if (ref.owner is ClassRef) {
    return '${ref.owner.name}.${name}';
  } else if (ref.owner is FuncRef) {
    return '${printFunctionName(ref.owner, terse: true)}.${name}';
  } else {
    return name;
  }
}

Point _calcPos(Script script, int tokenPos) {
  List<List<int>> table = script.tokenPosTable;

  for (List<int> row in table) {
    int line = row[0];

    int index = 1;

    while (index < row.length - 1) {
      if (row[index] == tokenPos) return new Point.coords(line, row[index + 1]);
      index += 2;
    }
  }

  return null;
}

class ObservatoryLog extends Log {
  final Logger logger;

  ObservatoryLog(this.logger);

  void warning(String message) => logger.warning(message);
  void severe(String message) => logger.severe(message);
}
