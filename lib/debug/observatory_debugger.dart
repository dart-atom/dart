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
import 'model.dart';

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
      launch.addDebugConnection(new ObservatoryConnection(
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

class ObservatoryConnection extends DebugConnection {
  final VmService service;
  final Completer completer;
  final bool pipeStdio;
  final bool isolatesStartPaused;

  Map<String, ObservatoryIsolate> _isolateMap = {};

  StreamSubscriptions subs = new StreamSubscriptions();
  UriResolver uriResolver;

  bool stdoutSupported = true;
  bool stderrSupported = true;

  ObservatoryConnection(Launch launch, this.service, this.completer, {
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

  // TODO: Temp.
  ObservatoryIsolate __isolate;
  ObservatoryIsolate get _isolate {
    if (__isolate == null) {
      // TODO: remove this
      __isolate = new ObservatoryIsolate._(this, service, null);
    }
    return __isolate;
  }
  set _currentIsolate(IsolateRef val) {
    _isolate.isolateRef = val;
    if (_isolate.isolate == null) _isolate._updateIsolateInfo();
    //__isolate = _isolateMap[val.id];
  }
  IsolateRef get _currentIsolate => _isolate.isolateRef;
  DebugIsolate get isolate => _isolate; //isolates.items.first;

  Future resume() => isolate.resume();
  stepIn() => isolate.stepIn();
  stepOver() => isolate.stepOver();
  stepOut() => isolate.stepOut();

  Future terminate() => launch.kill();

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

    // Handle the dart:developer log() calls.
    service.onEvent('_Logging').listen((Event e) {
      var json = e.json['logRecord'];

      // num time = json['time'];
      // num level = json['level'];
      // InstanceRef error = InstanceRef.parse(json['error']);
      // InstanceRef stackTrace = InstanceRef.parse(json['stackTrace']);
      InstanceRef loggerName = InstanceRef.parse(json['loggerName']);
      InstanceRef message = InstanceRef.parse(json['message']);

      String name = loggerName.valueAsString;
      if (name == null || name.isEmpty) {
        launch.pipeStdio('${message.valueAsString}\n', highlight: true);
      } else {
        launch.pipeStdio('[${name}] ${message.valueAsString}\n', highlight: true);
      }
    });
    service.streamListen('_Logging');

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
      String dartVersion = vm.version;
      if (dartVersion.contains(' ')) {
        dartVersion = dartVersion.substring(0, dartVersion.indexOf(' '));
      }
      metadata.value = '${vm.targetCPU} • ${vm.hostCPU} • Dart ${dartVersion}';
      _logger.info('Connected to ${metadata.value}');

      _registerNewIsolates(vm.isolates);

      if (!isolatesStartPaused && vm.isolates.isNotEmpty) {
        _currentIsolate = vm.isolates.first;
        _installInto(_currentIsolate).then((_) {
          _isolate._suspend(false);
        });
      } else if (isolatesStartPaused && vm.isolates.isNotEmpty) {
        if (_currentIsolate == null) {
          _currentIsolate = vm.isolates.first;
          _installInto(_currentIsolate).then((_) {
            service.getIsolate(_currentIsolate.id).then((Isolate isolate) {
              if (isolate.pauseEvent.kind == EventKind.kPauseStart) {
                _isolate.resume();
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
        _currentIsolate.id, ExceptionPauseMode.kUnhandled);
    });
  }

  bool _startIt = false;

  void _handleIsolateEvent(Event e) {
    // TODO: Create an isolate handler.

    launch.pipeStdio('${e}\n', subtle: true);

    if (e.kind == EventKind.kIsolateStart) {
      _registerNewIsolates([e.isolate]);
    } else if (e.kind == EventKind.kIsolateRunnable) {
      _handleIsolateRunnable(e.isolate);
    } else if (e.kind == EventKind.kIsolateExit) {
      _handleIsolateDeath(e.isolate);
    }

    // IsolateStart, IsolateRunnable, IsolateExit, IsolateUpdate
    if (e.kind == EventKind.kIsolateRunnable) {
      // Don't re-init if it is already inited.
      if (_currentIsolate == null) {
        _currentIsolate = e.isolate;
        _installInto(_currentIsolate).then((_) {
          if (isolatesStartPaused) {
            _isolate.resume();
          }
        });
      } else if (_startIt) {
        _startIt = false;
        _isolate.resume();
      }
    } else if (e.kind == EventKind.kIsolateExit) {
      _currentIsolate = null;
    }
  }

  void _handleDebugEvent(Event e) {
    // TODO:
    if (e.kind == EventKind.kInspect) {
      InstanceRef ref = e.inspectee;
      if (ref.valueAsString != null) {
        launch.pipeStdio('${ref.valueAsString}\n');
      }
      launch.pipeStdio('${ref}\n');
    }

    if (e.kind == EventKind.kResume) {
      this._isolate._suspend(false);
    } else if (e.kind == EventKind.kPauseStart || e.kind == EventKind.kPauseExit ||
        e.kind == EventKind.kPauseBreakpoint || e.kind == EventKind.kPauseInterrupted ||
        e.kind == EventKind.kPauseException) {
      this._isolate._populateFrames().then((_) {
        this._isolate._suspend(true);
      });
    }

    if (e.kind == EventKind.kResume || e.kind == EventKind.kIsolateExit) {
      // TODO: isolate is resumed

    }

    if (e.kind != EventKind.kResume && e.topFrame != null) {
      if (e.exception != null) _printException(e.exception);
    }
  }

  void _printException(InstanceRef exception) {
    launch.pipeStdio('exception: ${_refToString(exception)}\n', error: true);
  }

  Future _registerNewIsolates(List<IsolateRef> refs) {
    List<Future> futures = [];

    for (IsolateRef ref in refs) {
      if (_isolateMap.containsKey(ref.id)) continue;

      ObservatoryIsolate isolate = new ObservatoryIsolate._(this, service, ref);
      _isolateMap[ref.id] = isolate;
      isolates.add(isolate);

      // Get isolate metadata.
      futures.add(isolate._updateIsolateInfo());
    }

    return Future.wait(futures);
  }

  Future _handleIsolateRunnable(IsolateRef ref) {
    ObservatoryIsolate isolate = _isolateMap[ref.id];

    if (isolate == null) {
      isolate = new ObservatoryIsolate._(this, service, ref);
      _isolateMap[ref.id] = isolate;
      isolates.add(isolate);
    }

    // Update the libraries list for the isolate.
    return isolate._updateIsolateInfo();
  }

  void _handleIsolateDeath(IsolateRef ref) {
    ObservatoryIsolate isolate = _isolateMap.remove(ref.id);
    if (isolate != null) isolates.remove(isolate);
  }

  void dispose() {
    subs.cancel();
    if (isAlive) terminate();
    uriResolver.dispose();
  }
}

String printFunctionName(FuncRef ref, {bool terse: false}) {
  String name = terse ? ref.name : '${ref.name}()';
  name = name.replaceAll('<anonymous closure>', '<anon>');

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
    if (ref.kind == InstanceKind.kString) {
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

class ObservatoryIsolate extends DebugIsolate {
  final ObservatoryConnection connection;
  final VmService service;
  /*final*/ IsolateRef isolateRef;
  Isolate isolate;
  ScriptManager scriptManager;

  ObservatoryIsolate._(this.connection, this.service, this.isolateRef) {
    scriptManager = new ScriptManager(service, this);
  }

  String get name => isolateRef?.name;

  String get id => isolateRef.id;

  List<DebugFrame> frames;

  List<ObservatoryLibrary> get libraries {
    if (isolate == null) return [];
    if (isolate.libraries == null) return [];

    return isolate.libraries.map(
      (libraryRef) => new ObservatoryLibrary._(libraryRef)).toList();
  }

  void _suspend(bool value) {
    if (!value) frames = null;
    suspended.value = value;
  }

  pause() => service.pause(isolateRef.id);
  Future resume() => service.resume(isolateRef.id);

  // TODO: only on suspend.
  stepIn() => service.resume(isolateRef.id, step: StepOption.kInto);
  stepOver() => service.resume(isolateRef.id, step: StepOption.kOver);
  stepOut() => service.resume(isolateRef.id, step: StepOption.kOut);

  Future _updateIsolateInfo() {
    return service.getIsolate(isolateRef.id).then((Isolate isolate) {
      this.isolate = isolate;

      print('isolate: ${isolate}, pauseEvent: ${isolate.pauseEvent}');
    });
  }

  // Populate the frames for the current isolate; populate the Scripts for any
  // referenced ScriptRefs.
  Future _populateFrames() {
    return service.getStack(id).then((Stack stack) {
      List<ScriptRef> scriptRefs = [];

      frames = stack.frames.map((Frame frame) {
        scriptRefs.add(frame.location.script);

        ObservatoryFrame obsFrame = new ObservatoryFrame(this, frame);
        obsFrame.locals = new List.from(
          frame.vars.map((v) => new ObservatoryVariable(v))
        );
        return obsFrame;
      }).toList();

      // TODO: Convert the messages into frames as well. The FuncRef will likely
      // be something like `Timer._handleMessage`. The 'locals' will be the
      // message data object; a closure reference?

      return scriptManager.loadAllScripts(scriptRefs);
    });
  }
}

class ObservatoryFrame extends DebugFrame {
  final ObservatoryIsolate isolate;
  final Frame frame;

  List<DebugVariable> locals;

  ObservatoryLocation _location;

  ObservatoryFrame(this.isolate, this.frame);

  String get title => printFunctionName(frame.function);

  DebugLocation get location {
    if (_location == null) {
      _location = new ObservatoryLocation(isolate, frame.location);
    }

    return _location;
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

  VmService get service => isolate.service;
}

class ObservatoryVariable extends DebugVariable {
  final BoundVariable variable;

  ObservatoryVariable(this.variable);

  String get name => variable.name;

  String get valueDescription => _refToString(variable.value);
}

class ObservatoryLocation extends DebugLocation {
  final ObservatoryIsolate isolate;
  final SourceLocation location;

  Completer _completer;

  ObservatoryLocation(this.isolate, this.location);

  String get path => _path;

  int get line => _pos?.row;
  int get column => _pos?.column;

  String get displayPath => location.script.uri;

  VmService get service => isolate.service;

  String _path;
  Point _pos;

  Future<DebugLocation> resolve() {
    if (_completer == null) {
      _completer = new Completer();

      _resolve().then((val) {
        _completer.complete(val);
      }).catchError((e) {
        _logger.info('${e}');
        _completer.complete(this);
      }).whenComplete(() {
        resolved = true;
      });
    }

    return _completer.future;
  }

  // TODO: Pre-populate the uri resolution - make this method synchronous.
  Future<DebugLocation> _resolve() {
    // This Script was already loaded when we populated the frames.
    Script script = isolate.scriptManager.getResolvedScript(location.script);

    // Get the line and column info.
    _pos = _calcPos(script, location.tokenPos);

    // Get the local path.
    return isolate.connection.uriResolver.resolveUriToPath(script.uri).then((String path) {
      _path = path;
      return this;
    });
  }
}

class ObservatoryLibrary implements Comparable<ObservatoryLibrary> {
  final LibraryRef _ref;

  ObservatoryLibrary._(LibraryRef ref) : _ref = ref;

  String get name => _ref.name;
  String get uri => _ref.uri;

  bool get private => uri.startsWith('dart:_');

  int get _kind {
    if (uri.startsWith('dart:')) return 2;
    if (uri.startsWith('package:') || uri.startsWith('package/')) return 1;
    return 0;
  }

  int compareTo(ObservatoryLibrary other) {
    int val = _kind - other._kind;
    if (val != 0) return val;
    return uri.compareTo(other.uri);
  }
}

class ScriptManager {
  final VmService service;
  final ObservatoryIsolate isolate;

  /// A Map from ScriptRef ids to retrieved Scripts.
  Map<String, Script> _scripts = {};
  Map<String, Completer<Script>> _scriptCompleters = {};

  ScriptManager(this.service, this.isolate);

  bool isScriptResolved(ScriptRef ref) => _scripts.containsKey(ref.id);

  /// Return an already resolved [Script]. This can return `null` if the script
  /// has not yet been loaded.
  Script getResolvedScript(ScriptRef scriptRef) {
    return _scripts[scriptRef.id];
  }

  Future<Script> resolveScript(ScriptRef scriptRef) {
    if (isScriptResolved(scriptRef)) {
      return new Future.value(getResolvedScript(scriptRef));
    }

    String refId = scriptRef.id;

    if (_scriptCompleters[refId] != null) {
      return _scriptCompleters[refId].future;
    }

    Completer<Script> completer = new Completer();
    _scriptCompleters[refId] = completer;

    service.getObject(isolate.id, refId).then((result) {
      if (result is Script) {
        _scripts[refId] = result;
        completer.complete(result);
      } else {
        completer.completeError(result);
      }
    }).catchError((e) {
      completer.completeError(e);
    }).whenComplete(() {
      _scriptCompleters.remove(refId);
    });

    return completer.future;
  }

  // Load all the given scripts.
  Future loadAllScripts(List<ScriptRef> refs) {
    List<Future> futures = [];

    for (ScriptRef ref in refs) {
      if (!_scripts.containsKey(ref.id)) {
        futures.add(resolveScript(ref));
      }
    }

    return Future.wait(futures);
  }
}
