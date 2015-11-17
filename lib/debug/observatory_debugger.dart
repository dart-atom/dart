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

    Completer<DebugConnection> connectedCompleter = new Completer();
    Completer finishedCompleter = new Completer();

    ws.onOpen.listen((_) {
      connectedCompleter.complete();

      VmService service = new VmService(
        ws.onMessage.map((MessageEvent e) => e.data as String),
        (String message) => ws.send(message),
        log: new ObservatoryLog(_logger)
      );

      _logger.info('Connected to observatory on ${url}.');
      launch.addDebugConnection(new ObservatoryDebugConnection(
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

class ObservatoryDebugConnection extends DebugConnection {
  final VmService service;
  final Completer completer;
  final bool pipeStdio;
  final bool isolatesStartPaused;

  IsolateRef _currentIsolate;
  StreamSubscriptions subs = new StreamSubscriptions();
  UriResolver uriResolver;

  bool stdoutSupported = true;
  bool stderrSupported = true;

  Property<bool> _suspended = new Property();
  ObservatoryDebugFrame topFrame;

  ObservatoryDebugConnection(Launch launch, this.service, this.completer, {
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
  bool get isSuspended => _suspended.value;

  // TODO: Temp.
  DebugIsolate get isolate {
    if (_currentIsolate == null) return null;
    return new ObservatoryDebugIsolate(_currentIsolate);
  }

  Stream<bool> get onSuspendChanged => _suspended.onChanged;

  pause() => service.pause(_currentIsolate.id);
  Future resume() => service.resume(_currentIsolate.id);

  // TODO: only on suspend.
  stepIn() => service.resume(_currentIsolate.id, step: StepOption.Into);
  stepOver() => service.resume(_currentIsolate.id, step: StepOption.Over);
  stepOut() => service.resume(_currentIsolate.id, step: StepOption.Out);

  terminate() => launch.kill();

  Future get onTerminated => completer.future;

  void _init() {
    var trim = (String str) => str.length > 1000 ? str.substring(0, 1000) + '…' : str;

    service.onSend.listen((str) {
      if (_logger.isLoggable(Level.FINER)) {
        _logger.finer('==> ${trim(str)}');
      }
    });

    service.onReceive.listen((str) {
      if (_logger.isLoggable(Level.FINER)) {
        _logger.finer('<== ${trim(str)}');
      }
    });

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
      } else if (isolatesStartPaused && vm.isolates.isNotEmpty) {
        if (_currentIsolate == null) {
          _currentIsolate = vm.isolates.first;
          _installInto(_currentIsolate).then((_) {
            service.getIsolate(_currentIsolate.id).then((Isolate isolate) {
              if (isolate.pauseEvent.kind == EventKind.PauseStart) {
                resume();
              } else {
                _startIt = true;
              }
            });
          });
        }
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

  bool _startIt = false;

  void _handleIsolateEvent(Event e) {
    // TODO: Create an isolate handler.

    launch.pipeStdio('${e}\n', subtle: true);

    // IsolateStart, IsolateRunnable, IsolateExit, IsolateUpdate
    if (e.kind == EventKind.IsolateRunnable) {
      // Don't re-init if it is already inited.
      if (_currentIsolate == null) {
        _currentIsolate = e.isolate;
        _installInto(_currentIsolate).then((_) {
          if (isolatesStartPaused) {
            resume();
          }
        });
      } else if (_startIt) {
        _startIt = false;
        resume();
      }
    } else if (e.kind == EventKind.IsolateExit) {
      _currentIsolate = null;
    }
  }

  void _handleDebugEvent(Event e) {
    IsolateRef isolate = e.isolate;

    if (e.kind == EventKind.Resume) {
      _suspend(false);
    } else if (e.kind == EventKind.PauseStart || e.kind == EventKind.PauseExit ||
        e.kind == EventKind.PauseBreakpoint || e.kind == EventKind.PauseInterrupted ||
        e.kind == EventKind.PauseException) {
      _suspend(true);
    }

    if (e.kind == EventKind.Resume || e.kind == EventKind.IsolateExit) {
      // TODO: isolate is resumed

    }

    if (e.kind != EventKind.Resume && e.topFrame != null) {
      topFrame = new ObservatoryDebugFrame(this, service, isolate, e.topFrame);
      topFrame.locals = new List.from(
          e.topFrame.vars.map((v) => new ObservatoryDebugVariable(v)));
      topFrame.tokenPos = e.topFrame.location.tokenPos;
    }

    if (e.kind != EventKind.Resume && e.topFrame != null) {
      if (e.exception != null) _printException(e.exception);
    }
  }

  void _printException(InstanceRef exception) {
    launch.pipeStdio('exception: ${_refToString(exception)}\n', error: true);
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
    if (!value) topFrame = null;
    _suspended.value = value;
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

String _refToString(dynamic value) {
  if (value is InstanceRef) {
    InstanceRef ref = value as InstanceRef;
    if (ref.kind == InstanceKind.String) {
      // TODO: escape string chars
      return "'${ref.valueAsString}'";
    } else if (ref.valueAsString != null) {
      return ref.valueAsString;
    } else {
      return '[${ref.classRef.name} ${ref.id}]';
    }
  } else {
    return '${value}';
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

class ObservatoryDebugIsolate extends DebugIsolate {
  final IsolateRef isolateRef;

  ObservatoryDebugIsolate(this.isolateRef);

  String get name => isolateRef.name;
}

class ObservatoryDebugFrame extends DebugFrame {
  final ObservatoryDebugConnection connection;
  final VmService service;
  final IsolateRef isolate;
  final Frame frame;

  // TODO: Resolve to line:col.
  int tokenPos;

  List<DebugVariable> locals;

  ObservatoryDebugFrame(this.connection, this.service, this.isolate, this.frame);

  String get title => printFunctionName(frame.function);

  String get cursorDescription {
    return 'token ${tokenPos}';
  }

  Future<DebugLocation> getLocation() {
    ScriptRef scriptRef = frame.location.script;

    return connection._resolveScript(isolate, scriptRef).then((Script script) {
      int tokenPos = frame.location.tokenPos;
      Point pos = _calcPos(script, tokenPos);
      String uri = script.uri;

      if (pos != null) {
        return connection.uriResolver.resolveUriToPath(uri).then((String path) {
          return new DebugLocation(path, pos.row, pos.column);
        }).catchError((e) {
          atom.notifications.addWarning(
              "Unable to resolve '${uri}' (${pos.row}:${pos.column}).");
        });
      }
    });
  }

  @override
  Future<String> eval(String expression) {
    return service.evaluateInFrame(isolate.id, frame.index, expression).then((result) {
      // [InstanceRef] or [ErrorRef]
      if (result is ErrorRef) {
        throw result.message;
      } else {
        return _refToString(result);
      }
    });
  }
}

class ObservatoryDebugVariable extends DebugVariable {
  final BoundVariable variable;

  ObservatoryDebugVariable(this.variable);

  String get name => variable.name;

  String get valueDescription => _refToString(variable.value);
}
