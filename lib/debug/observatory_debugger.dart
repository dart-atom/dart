library atom.observatory_debugger;

import 'dart:async';

import 'package:atom/node/fs.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import '../flutter/flutter_ext.dart';
import '../launch/launch.dart';
import '../state.dart';
import 'breakpoints.dart';
import 'debugger.dart';
import 'model.dart';
import 'observatory.dart';
import 'utils.dart';
import 'websocket.dart';

final Logger _logger = new Logger('atom.observatory');

const _verbose = false;

class ObservatoryDebugger {
  /// Establish a connection to a service protocol server at the given port.
  static Future<DebugConnection> connect(Launch launch, String host, int port, {
    UriTranslator uriTranslator,
    bool pipeStdio: false
  }) {
    String url = 'ws://${host}:${port}/ws';

    WebSocket ws = new WebSocket(url);

    Completer<DebugConnection> connectedCompleter = new Completer();
    Completer finishedCompleter = new Completer();

    ws.onOpen.listen((_) {
      _logger.info('Connected to observatory on ${url}.');

      VmService service = new VmService(
        ws.onMessage.map((MessageEvent e) => e.data as String),
        (String message) => ws.send(message),
        log: new ObservatoryLog(_logger)
      );

      ObservatoryConnection connection = new ObservatoryConnection(
        launch,
        service,
        finishedCompleter,
        uriTranslator: uriTranslator,
        pipeStdio: pipeStdio,
        ws: ws
      );

      launch.addDebugConnection(connection);
      connectedCompleter.complete(connection);
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
  final WebSocket ws;

  Map<String, ObservatoryIsolate> _isolateMap = {};

  StreamController<DebugIsolate> _isolatePaused = new StreamController.broadcast();
  StreamController<DebugIsolate> _isolateResumed = new StreamController.broadcast();

  StreamController<ObservatoryIsolate> _isolateCreatedController = new StreamController.broadcast();

  _VmSourceCache sourceCache = new _VmSourceCache();

  StreamSubscriptions subs = new StreamSubscriptions();
  UriResolver uriResolver;

  bool stdoutSupported = true;
  bool stderrSupported = true;

  int _nextIsolateId = 1;
  FlutterExt flutterExtension;

  ObservatoryConnection(Launch launch, this.service, this.completer, {
    this.pipeStdio: false,
    UriTranslator uriTranslator,
    this.ws
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

  Stream<DebugIsolate> get onPaused => _isolatePaused.stream;
  Stream<DebugIsolate> get onResumed => _isolateResumed.stream;

  // TODO: The UI should be in charge of servicing the connection level flow
  // control commands.
  DebugIsolate get _selectedIsolate => isolates.selection;

  Future resume() {
    if (_selectedIsolate != null) return _selectedIsolate?.resume();
    return new Future.value();
  }

  stepIn() => _selectedIsolate?.stepIn();
  stepOver() => _selectedIsolate?.stepOver();
  stepOut() => _selectedIsolate?.stepOut();
  stepOverAsyncSuspension() => _selectedIsolate?.stepOverAsyncSuspension();
  autoStepOver() => _selectedIsolate?.autoStepOver();

  Future terminate() {
    try { ws?.close(); } catch (e) { }
    return launch.kill();
  }

  Future get onTerminated => completer.future;

  ObservatoryIsolate _getIsolate(IsolateRef ref) => _isolateMap[ref.id];

  void _init() {
    var trim = (String str) => str.length > 1000 ? str.substring(0, 1000) + '…' : str;

    service.onSend.listen((str) {
      if (_verbose || _logger.isLoggable(Level.FINER)) {
        _logger.fine('==> ${trim(str)}');
      }
    });

    service.onReceive.listen((str) {
      if (_verbose || _logger.isLoggable(Level.FINER)) {
        _logger.fine('<== ${trim(str)}');
      }
    });

    // Handle the dart:developer log() calls.
    service.onEvent('_Logging').listen((Event e) {
      Map json = e.json['logRecord'];
      // num time = json['time'];
      // num level = json['level'];
      // InstanceRef error = InstanceRef.parse(json['error']);
      // InstanceRef stackTrace = InstanceRef.parse(json['stackTrace']);
      InstanceRef loggerName = InstanceRef.parse(new Map.from(json['loggerName']));
      InstanceRef message = InstanceRef.parse(new Map.from(json['message']));

      String name = loggerName.valueAsString;
      if (name == null || name.isEmpty) {
        launch.pipeStdio('${message.valueAsString}\n', highlight: true);
      } else {
        launch.pipeStdio('[${name}] ${message.valueAsString}\n', highlight: true);
      }
    });
    service.streamListen('_Logging');

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

    flutterExtension = new FlutterExt(new _ObservatoryServiceWrapper(this));

    service.getVM().then((VM vm) {
      String dart = vm.version;
      if (dart.contains(' ')) dart = dart.substring(0, dart.indexOf(' '));
      metadata.value = '${vm.targetCPU} • ${vm.hostCPU} • Dart ${dart}';
      _logger.info('Connected to ${metadata.value}');
      return _registerNewIsolates(vm.isolates);
    });
  }

  // TODO: Create an observatory breakpoint manager class.
  Future _installBreakpoints(IsolateRef isolate) {
    Map<AtomBreakpoint, List<Breakpoint>> _bps = {};

    var addBreakpoint = (AtomBreakpoint atomBreakpoint, Breakpoint vmBreakpoint) {
      if (!_bps.containsKey(atomBreakpoint)) _bps[atomBreakpoint] = <Breakpoint>[];
      _bps[atomBreakpoint].add(vmBreakpoint);
    };

    // TODO: This will try and set breakpoints on dead isolates.
    subs.add(breakpointManager.onAdd.listen((AtomBreakpoint bp) {
      uriResolver.resolvePathToUris(bp.path).then((List<String> uris) {
        return Future.forEach(uris, (String uri) {
          return service.addBreakpointWithScriptUri(
            isolate.id,
            uri,
            bp.line,
            column: bp.column
          ).then((Breakpoint vmBreakpoint) {
            addBreakpoint(bp, vmBreakpoint);
          }).catchError((e) {
            // ignore
          });
        });
      }).catchError((e) {
        _logger.info('error resolving uri: ${bp.path}', '${e}');
      });
    }));

    subs.add(breakpointManager.onRemove.listen((AtomBreakpoint bp) {
      List<Breakpoint> breakpoints = _bps[bp];
      if (breakpoints != null) {
        for (Breakpoint vmBreakpoint in breakpoints) {
          service.removeBreakpoint(isolate.id, vmBreakpoint.id).catchError((e) {
            _logger.info('error removing breakpoint', e);
          });
        }
      }
    }));

    // This handles self-references and editor breakpoints multiplexed over
    // several VM breakpoints.
    return Future.forEach(breakpointManager.breakpoints, (AtomBreakpoint bp) {
      if (!bp.fileExists()) return null;

      return uriResolver.resolvePathToUris(bp.path).then((List<String> uris) {
        return Future.forEach(uris, (String uri) {
          return service.addBreakpointWithScriptUri(
            isolate.id,
            uri,
            bp.line,
            column: bp.column
          ).then((Breakpoint vmBreakpoint) {
            addBreakpoint(bp, vmBreakpoint);
          }).catchError((e) {
            // ignore
          });
        });
      });
    }).then((_) {
      // TODO(devoncarew): Listen for changes to the exception pause mode and
      // update the isolate.
      return service.setExceptionPauseMode(isolate.id, _getExceptionPauseMode());
    });
  }

  void _handleIsolateEvent(Event event) {
    // IsolateStart, IsolateRunnable, IsolateUpdate, IsolateExit
    IsolateRef ref = event.isolate;

    switch (event.kind) {
      case EventKind.kIsolateStart:
        _registerNewIsolate(ref);
        break;
      case EventKind.kIsolateRunnable:
        _installBreakpoints(ref).then((_) {
          _updateIsolateMetadata(ref).then((ObservatoryIsolate obsIsolate) {
            obsIsolate.isolate.runnable = true;
            if (obsIsolate._wasPauseAtStart) {
              obsIsolate._isolateInitializedCompleter.future.then((_) {
                obsIsolate._performInitialResume();
              });
            }
          });
        });
        break;
      case EventKind.kIsolateUpdate:
        _updateIsolateMetadata(ref);
        break;
      case EventKind.kIsolateExit:
        _handleIsolateDeath(ref);
        break;
    }
  }

  // PauseStart, PauseExit, PauseBreakpoint, PauseInterrupted, PauseException,
  // Resume, BreakpointAdded, BreakpointResolved, BreakpointRemoved, Inspect
  void _handleDebugEvent(Event event) {
    String kind = event.kind;
    IsolateRef ref = event.isolate;

    switch (kind) {
      case EventKind.kPauseStart:
        _registerNewIsolate(ref).then((ObservatoryIsolate obsIsolate) {
          obsIsolate._wasPauseAtStart = true;
          obsIsolate._isolateInitializedCompleter.future.then((_) {
            obsIsolate._performInitialResume();
          });
        });
        break;
      case EventKind.kPauseExit:
      case EventKind.kPauseBreakpoint:
      case EventKind.kPauseInterrupted:
      case EventKind.kPauseException:
        ObservatoryIsolate isolate = _getIsolate(ref);

        if (event.exception != null) {
          _printExceptionToConsole(isolate, event.exception);
        }

        isolate._populateFrames(exception: event.exception).then((_) {
          bool asyncSuspension = event.atAsyncSuspension == null ? false : event.atAsyncSuspension;
          isolate._suspend(true, pausedAtAsyncSuspension: asyncSuspension);
        });
        break;
      case EventKind.kResume:
        _getIsolate(ref)?._suspend(false, pausedAtAsyncSuspension: false);
        break;
      case EventKind.kInspect:
        InstanceRef inspectee = event.inspectee;
        if (inspectee.valueAsString != null) {
          launch.pipeStdio('${inspectee.valueAsString}\n');
        } else {
          launch.pipeStdio('${inspectee}\n');
        }
        break;
    }
  }

  // TODO: Move much of the isolate lifecycle code into a manager class.
  // TODO: Make the isolate bring-up lifecycle clearer.
  // TODO: Don't set breakpoints until the isolate runnable events is received
  //       (with the caveat: don't resume isolate until we've set breakpoints).

  Future<ObservatoryIsolate> _registerNewIsolate(IsolateRef ref) {
    if (_isolateMap.containsKey(ref.id)) return new Future.value(_isolateMap[ref.id]);

    ObservatoryIsolate isolate = new ObservatoryIsolate._(this, service, ref);
    _isolateMap[ref.id] = isolate;
    isolates.add(isolate);

    // Get isolate metadata.
    return isolate._updateIsolateInfo().then(([ObservatoryIsolate _]) {
      // If the isolate is currently runnable, or the protocol does not have
      // information about its runnability, then set breakpoints at this time.
      if (isolate._runnable) return _installBreakpoints(ref);
    }).then((_) {
      isolate._isolateInitializedCompleter.complete();

      if (isolate.isolate.pauseEvent?.kind == EventKind.kPauseStart) {
        isolate._performInitialResume();
      }

      _isolateCreatedController.add(isolate);

      return isolate;
    });
  }

  Future<List<ObservatoryIsolate>> _registerNewIsolates(List<IsolateRef> refs) {
    List<Future<ObservatoryIsolate>> futures = [];

    for (IsolateRef ref in refs) {
      futures.add(_registerNewIsolate(ref));
    }

    return Future.wait(futures);
  }

  Future<ObservatoryIsolate> _updateIsolateMetadata(IsolateRef ref) {
    ObservatoryIsolate isolate = _isolateMap[ref.id];

    if (isolate == null) {
      return _registerNewIsolate(ref);
    } else {
      // Update the libraries list for the isolate.
      return isolate._updateIsolateInfo();
    }
  }

  String _getExceptionPauseMode() {
    ExceptionBreakType val = breakpointManager.breakOnExceptionType;

    if (val == ExceptionBreakType.all) return ExceptionPauseMode.kAll;
    if (val == ExceptionBreakType.none) return ExceptionPauseMode.kNone;

    return ExceptionPauseMode.kUnhandled;
  }

  void _printExceptionToConsole(ObservatoryIsolate isolate, InstanceRef exception) {
    if (exception.kind == InstanceKind.kString || exception.valueAsString != null) {
      String message = exception.kind == InstanceKind.kString ?
        "'${exception.valueAsString}'" : exception.valueAsString;
      launch.pipeStdio("exception: $message\n", error: true);
    } else {
      launch.pipeStdio('exception (${exception.classRef.name}): ', error: true);

      var exceptionRef = new ObservatoryInstanceRefValue(isolate, exception);
      exceptionRef.invokeToString().then((DebugValue result) {
        String str = result.valueAsString;
        if (result.valueIsTruncated) str += '…';
        launch.pipeStdio('"${str.trimRight()}"\n', error: true);
      }).catchError((e) {
        _logger.info('Error invoking toString on exception: $e');
        launch.pipeStdio('\n', error: true);
      });
    }
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
  return name = name.replaceAll('<anonymous closure>', '<anon>');
}

String printFunctionNameRecursive(FuncRef ref, {bool terse: false}) {
  String name = terse ? ref.name : '${ref.name}()';
  name = name.replaceAll('<anonymous closure>', '<anon>');

  if (ref.owner is ClassRef) {
    return '${ref.owner.name}.${name}';
  } else if (ref.owner is FuncRef) {
    return '${printFunctionNameRecursive(ref.owner, terse: true)}.${name}';
  } else {
    return name;
  }
}

String _refToString(dynamic value) {
  if (value is InstanceRef) {
    InstanceRef ref = value;
    if (ref.kind == InstanceKind.kString) {
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
  final IsolateRef isolateRef;

  Completer _isolateInitializedCompleter = new Completer();

  Isolate isolate;
  ScriptManager scriptManager;

  bool suspended = false;
  bool suspendedAtAsyncSuspension = false;
  bool _didInitialResume = false;
  bool _wasPauseAtStart = false;

  String _detail;

  ObservatoryIsolate._(this.connection, this.service, this.isolateRef) {
    scriptManager = new ScriptManager(service, this);
    _detail = '#${connection._nextIsolateId++}';
  }

  String get name => isolateRef.name;

  // Isolate names are something like `foo_app.dart$main`. This cleans them up
  // slightly to `foo_app.dart:main()`.
  String get displayName => name.contains(r'$') ? "${name.replaceAll(r'$', ':')}()" : name;

  String get detail => _detail;

  String get id => isolateRef.id;

  List<DebugFrame> frames;

  List<ObservatoryLibrary> get libraries {
    if (isolate == null) return [];
    if (isolate.libraries == null) return [];

    return isolate.libraries.map(
      (libraryRef) => new ObservatoryLibrary._(libraryRef)).toList();
  }

  /// If the isolate is currently runnable (or the protocol does not have
  /// information about its runnability) return true.
  bool get _runnable => isolate.runnable == null || isolate.runnable == true;

  void _suspend(bool paused, {bool pausedAtAsyncSuspension: false}) {
    if (!paused) {
      frames = null;
      suspendedAtAsyncSuspension = false;
    }

    suspended = paused;
    suspendedAtAsyncSuspension = pausedAtAsyncSuspension;

    if (paused) {
      connection._isolatePaused.add(this);
    } else {
      connection._isolateResumed.add(this);
    }

    // TODO: Remove this.
    if (suspended) {
      connection.isolates.setSelection(this);
    }
  }

  pause() => service.pause(isolateRef.id);
  Future resume() => service.resume(isolateRef.id);

  stepIn() => service.resume(isolateRef.id, step: StepOption.kInto);
  stepOver() => service.resume(isolateRef.id, step: StepOption.kOver);
  stepOut() => service.resume(isolateRef.id, step: StepOption.kOut);
  stepOverAsyncSuspension() => service.resume(isolateRef.id, step: StepOption.kOverAsyncSuspension);
  autoStepOver() => suspendedAtAsyncSuspension ? stepOverAsyncSuspension() : stepOver();

  Future<ObservatoryIsolate> _updateIsolateInfo() {
    return service.getIsolate(isolateRef.id).then((Isolate isolate) {
      this.isolate = isolate;
      return this;
    });
  }

  // Populate the frames for the current isolate; populate the Scripts for any
  // referenced ScriptRefs.
  Future _populateFrames({ InstanceRef exception }) {
    return service.getStack(id).then((Stack stack) {
      List<ScriptRef> scriptRefs = [];

      frames = stack.frames.map((Frame frame) {
        scriptRefs.add(frame.location.script);

        ObservatoryFrame obsFrame = new ObservatoryFrame(this, frame, isExceptionFrame: exception != null);

        obsFrame.locals = new List.from(
          frame.vars.map((BoundVariable v) => new ObservatoryVariable(this, v))
        );

        if (exception != null) {
          BoundVariable exceptionVariable = new BoundVariable()
            ..name = 'exception'
            ..value = exception;
          obsFrame.locals.insert(0, new ObservatoryVariable(this, exceptionVariable));

          exception = null;
        }

        return obsFrame;
      }).toList();

      // TODO: Convert the messages into frames as well. The FuncRef will likely
      // be something like `Timer._handleMessage`. The 'locals' will be the
      // message data object; a closure reference?

      return scriptManager.loadAllScripts(scriptRefs);
    });
  }

  int get hashCode => id.hashCode;

  bool operator==(other) {
    if (other is! ObservatoryIsolate) return false;
    return id == other.id;
  }

  String toString() => 'Isolate ${name}';

  void _performInitialResume() {
    if (_didInitialResume) return;

    if (isolate != null && _runnable) {
      _didInitialResume = true;
      resume();
    }
  }
}

class ObservatoryFrame extends DebugFrame {
  final ObservatoryIsolate isolate;
  final Frame frame;
  final bool isExceptionFrame;

  List<DebugVariable> locals;

  ObservatoryLocation _location;

  ObservatoryFrame(this.isolate, this.frame, { this.isExceptionFrame: false });

  String get title => printFunctionNameRecursive(frame.function);

  bool get isSystem => (location as ObservatoryLocation).isSystem;

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
  final BoundVariable _variable;
  final DebugValue value;

  ObservatoryVariable(ObservatoryIsolate isolate, BoundVariable variable) :
    _variable = variable, value = _createValue(isolate, variable);

  String get name => _variable.name;

  static DebugValue _createValue(ObservatoryIsolate isolate, BoundVariable variable) {
    if (variable.value is InstanceRef) {
      return new ObservatoryInstanceRefValue(isolate, variable.value);
    } else if (variable.value is Sentinel) {
      return new SentinelDebugValue(variable.value);
    } else {
      return null;
    }
  }

  String toString() => 'ObservatoryVariable ${name}';
}

class ObservatoryFieldVariable extends DebugVariable {
  final BoundField _field;
  final DebugValue value;

  ObservatoryFieldVariable(ObservatoryIsolate isolate, BoundField field) :
    _field = field, value = _createValue(isolate, field);

  String get name => _field.decl.name;

  static DebugValue _createValue(ObservatoryIsolate isolate, BoundField field) {
    if (field.value is InstanceRef) {
      return new ObservatoryInstanceRefValue(isolate, field.value);
    } else if (field.value is Sentinel) {
      return new SentinelDebugValue(field.value);
    } else {
      return null;
    }
  }
}

class ObservatoryMapVariable extends DebugVariable {
  final ObservatoryIsolate isolate;
  final MapAssociation association;

  ObservatoryInstanceRefValue _value;

  ObservatoryMapVariable(this.isolate, this.association) {
    _value = new ObservatoryInstanceRefValue(isolate, association.value);
  }

  String get name => '${_instanceToString(association.key)}:';

  DebugValue get value => _value;
}

class ObservatoryArrayVariable extends DebugVariable {
  final ObservatoryIsolate isolate;
  final int index;
  DebugValue _value;

  ObservatoryArrayVariable(this.isolate, this.index, dynamic value) {
    if (value is InstanceRef) {
      _value = new ObservatoryInstanceRefValue(isolate, value);
    } else if (value is Sentinel) {
      _value = new SentinelDebugValue(value);
    }
  }

  String get name => '[${index}]';

  DebugValue get value => _value;
}

class ObservatoryCustomVariable extends DebugVariable {
  final String name;
  final DebugValue value;

  ObservatoryCustomVariable(this.name, dynamic inValue) :
    value = new SimpleDebugValue(inValue);
}

class ObservatoryObjRefVariable extends DebugVariable {
  final ObservatoryIsolate isolate;
  final String name;
  DebugValue _value;

  ObservatoryObjRefVariable(this.isolate, this.name, dynamic ref) {
    if (ref is Sentinel) {
      _value = new SentinelDebugValue(ref);
    } else if (ref is ObjRef) {
      _value = new ObservatoryObjRefValue(isolate, ref);
    } else {
      _logger.severe('Invalid ObservatoryObjRefVariable ref: ${ref}');
    }
  }

  DebugValue get value => _value;
}

class ObservatoryInstanceRefValue extends DebugValue {
  final ObservatoryIsolate isolate;
  final InstanceRef value;

  ObservatoryInstanceRefValue(this.isolate, this.value);

  factory ObservatoryInstanceRefValue.fromInstance(
    ObservatoryIsolate isolate,
    Instance instance
  ) {
    InstanceRef ref = new InstanceRef();
    ref.type = instance.type; // TODO:
    ref.id = instance.id;
    ref.kind = instance.kind;
    ref.classRef = instance.classRef;
    ref.valueAsString = instance.valueAsString;
    ref.valueAsStringIsTruncated = instance.valueAsStringIsTruncated;
    ref.length = instance.length;
    ref.name = instance.name;
    ref.typeClass = instance.typeClass;
    ref.parameterizedClass = instance.parameterizedClass;
    // ref.pattern = instance.pattern;
    return new ObservatoryInstanceRefValue(isolate, ref);
  }

  String get className => value.classRef.name;

  bool get isPrimitive {
    String kind = value.kind;
    return kind == InstanceKind.kNull ||
      kind == InstanceKind.kBool ||
      kind == InstanceKind.kDouble ||
      kind == InstanceKind.kInt ||
      kind == InstanceKind.kString;
  }

  bool get isString => value.kind == InstanceKind.kString;
  bool get isPlainInstance => value.kind == InstanceKind.kPlainInstance;
  bool get isList => value.kind == InstanceKind.kList;
  bool get isMap => value.kind == InstanceKind.kMap;

  bool get valueIsTruncated {
    return value.valueAsStringIsTruncated == null ? false : value.valueAsStringIsTruncated;
  }

  int get itemsLength => value.length;

  Future<List<DebugVariable>> getChildren() {
    // TODO: Handle typed lists (bytes).
    // TODO: Handle regex values (pattern).
    // TODO: Handle mirrors (mirrorReferent).

    return isolate.service.getObject(isolate.id, value.id).then((ret) {
      if (ret is Instance) {
        if (ret.kind == InstanceKind.kMap) {
          return ret.associations.map((MapAssociation association) {
            return new ObservatoryMapVariable(isolate, association);
          }).toList();
        } else if (ret.kind == InstanceKind.kList) {
          // TODO: Handle lists with lots of entries.
          List<DebugVariable> results = [];
          List elements = ret.elements;
          for (int i = 0; i < elements.length; i++) {
            results.add(
              new ObservatoryArrayVariable(isolate, i, elements[i])
            );
          }
          return results;
        } else if (ret.kind == InstanceKind.kPlainInstance) {
          return ret.fields.map((BoundField field) {
            return new ObservatoryFieldVariable(isolate, field);
          }).toList();
        } else if (ret.kind == InstanceKind.kClosure) {
          // TODO: load the Obj instead (show location, code).
          List<DebugVariable> results = [];
          FuncRef function = ret.closureFunction;
          results.add(new ObservatoryCustomVariable('name', printFunctionName(function)));
          results.add(new ObservatoryObjRefVariable(isolate, 'owner', function.owner));
          return results;
        } else {
          _logger.info('unhandled debugger type: ${ret.kind}');
          return ret.fields.map((BoundField field) {
            return new ObservatoryFieldVariable(isolate, field);
          }).toList();
        }
      } else {
        return [];
      }
    });
  }

  Future<DebugValue> invokeToString() async {
    dynamic result = await isolate.service.evaluate(isolate.id, value.id, 'toString()');

    // [InstanceRef], [ErrorRef] or [Sentinel]
    if (result is Sentinel) {
      return new SentinelDebugValue(result);
    } else if (result is InstanceRef) {
      InstanceRef ref = result;
      if (ref.kind == InstanceKind.kString && ref.valueAsStringIsTruncated == true) {
        return isolate.service.getObject(isolate.id, result.id).then((result) {
          if (result is Sentinel) {
            return new SentinelDebugValue(result);
          } else if (result is InstanceRef) {
            return new ObservatoryInstanceRefValue(isolate, result);
          } else if (result is Instance) {
            return new ObservatoryInstanceRefValue.fromInstance(isolate, result);
          } else if (result is ErrorRef) {
            return new Future.error(result.message);
          } else {
            return new Future.error('unexpected result type: ${result}');
          }
        });
      } else {
        return new ObservatoryInstanceRefValue(isolate, result);
      }
    } else if (result is ErrorRef) {
      throw result.message;
    } else {
      throw 'unexpected result type: ${result}';
    }
  }

  String get valueAsString {
    if (value.valueAsString != null) {
      return value.valueAsString;
    }

    if (value.kind == InstanceKind.kClosure) {
      return '() =>';
    }

    return null;
  }

  String toString() => 'ObservatoryValue ${className}';
}

// TODO: We probably shouldn't expose these values directly to the user.
// TODO: For LibraryRef, FuncRef, also include the location to jump to.
class ObservatoryObjRefValue extends DebugValue {
  final ObservatoryIsolate isolate;
  final ObjRef ref;

  ObservatoryObjRefValue(this.isolate, this.ref);

  String get className => ref.runtimeType.toString();

  bool get isPrimitive {
    if (ref is FuncRef) return false;

    return true;
  }

  bool get isString => false;
  bool get isPlainInstance => false;
  bool get isList => false;
  bool get isMap => false;

  bool get valueIsTruncated => false;

  int get itemsLength => null;

  // ClassRef, Code, CodeRef, ContextRef, ErrorRef, FieldRef, FuncRef,
  // InstanceRef?, LibraryRef, ScriptRef, TypeArgumentsRef

  Future<List<DebugVariable>> getChildren() {
    if (ref is FuncRef) {
      FuncRef function = ref;

      List<DebugVariable> results = [];
      results.add(new ObservatoryCustomVariable('name', printFunctionName(function)));
      results.add(new ObservatoryObjRefVariable(isolate, 'owner', function.owner));
      return new Future.value(results);
    } else if (ref is LibraryRef) {
      LibraryRef lib = ref;

      List<DebugVariable> results = [];
      results.add(new ObservatoryCustomVariable('name', lib.name));
      results.add(new ObservatoryCustomVariable('uri', lib.uri));
      return new Future.value(results);
    } else {
      return new Future.value([]);
    }
  }

  Future<DebugValue> invokeToString() {
    return new Future.value(new SimpleDebugValue(valueAsString));
  }

  // TODO: Handle more ObjRef types here.
  String get valueAsString {
    if (ref is FuncRef) return printFunctionName(ref);
    if (ref is LibraryRef) return 'Library ${getDisplayUri((ref as LibraryRef).uri)}';

    return '${className} ${ref.id}';
  }
}

class SimpleDebugValue extends DebugValue {
  final dynamic value;

  SimpleDebugValue(this.value);

  String get className => value.runtimeType.toString();

  String get valueAsString => value is String ? value : '${value}';

  bool get isPrimitive => true;
  bool get isString => false; //value is String;
  bool get isPlainInstance => false;
  bool get isList => false;
  bool get isMap => false;

  bool get valueIsTruncated => false;

  int get itemsLength => null;

  Future<List<DebugVariable>> getChildren() => new Future.value([]);

  Future<DebugValue> invokeToString() => new Future.value(this);
}

class SentinelDebugValue extends DebugValue {
  final Sentinel sentenial;

  SentinelDebugValue(this.sentenial);

  String get className => null;

  bool get isPrimitive => true;
  bool get isString => false;
  bool get isPlainInstance => false;
  bool get isList => false;
  bool get isMap => false;

  bool get valueIsTruncated => false;

  int get itemsLength => null;

  Future<List<DebugVariable>> getChildren() => new Future.value([]);

  Future<DebugValue> invokeToString() =>
    new Future.value(new SimpleDebugValue(valueAsString));

  String get valueAsString => sentenial.valueAsString;
}

class ObservatoryLocation extends DebugLocation {
  final ObservatoryIsolate isolate;
  final SourceLocation location;

  Completer<DebugLocation> _completer;
  bool _unableToResolve = false;

  ObservatoryLocation(this.isolate, this.location);

  String get path => _path;

  int get line => _pos?.row;
  int get column => _pos?.column;

  String get displayPath => location.script.uri;

  VmService get service => isolate.service;

  bool get isSystem => location.script.uri.startsWith('dart:') || _unableToResolve;

  String _path;
  Point _pos;

  Future<DebugLocation> resolve() {
    if (_completer == null) {
      _completer = new Completer<DebugLocation>();

      _resolve().then((DebugLocation val) {
        _completer.complete(val);
      }).catchError((e) {
        _completer.complete(this);
      }).whenComplete(() {
        resolved = true;
        _checkCreateSystemScript();
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

    _path = script.uri;

    // Get the local path.
    return isolate.connection.uriResolver.resolveUriToPath(script.uri).then((String path) {
      _path = path;
      return this;
    });
  }

  void _checkCreateSystemScript() {
    if (fs.existsSync(_path)) return;

    _unableToResolve = true;

    // Load the script from the VM.
    Script script = isolate.scriptManager.getResolvedScript(location.script);

    String cachedPath = isolate.connection.sourceCache.createRetrieveCachePath(
      _path, script.source);
    _path = cachedPath;
  }
}

class ObservatoryLibrary implements Comparable<ObservatoryLibrary> {
  final LibraryRef _ref;
  String _displayUri;

  ObservatoryLibrary._(LibraryRef ref) : _ref = ref;

  String get name => _ref.name;
  String get uri => _ref.uri;

  String get displayUri {
    if (_displayUri == null) {
      _displayUri = getDisplayUri(uri);
    }
    return _displayUri;
  }

  bool get private => uri.startsWith('dart:_');

  int get _kind {
    if (uri.startsWith('dart:')) return 2;
    if (uri.startsWith('package:') || uri.startsWith('package/')) return 1;
    return 0;
  }

  int compareTo(ObservatoryLibrary other) {
    int val = _kind - other._kind;
    if (val != 0) return val;
    return displayUri.compareTo(other.displayUri);
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

class _ObservatoryServiceWrapper implements ServiceWrapper {
  final ObservatoryConnection connection;

  _ObservatoryServiceWrapper(this.connection);

  VmService get service => connection.service;

  Iterable<ObservatoryIsolate> get allIsolates => new List.from(connection.isolates.items);

  Stream<ObservatoryIsolate> get onIsolateCreated => connection._isolateCreatedController.stream;

  Stream<ObservatoryIsolate> get onIsolateFinished => connection.isolates.onRemoved;
}

/// [instance] is either an [Instance] or a [Sentinel].
String _instanceToString(dynamic instance) {
  if (instance is InstanceRef || instance is Instance) {
    if (instance.kind == InstanceKind.kString) {
      return '"${instance.valueAsString}"';
    } else if (instance.valueAsString != null) {
      return instance.valueAsString;
    } else {
      return '[${instance.classRef.name}]';
    }
  } else if (instance is Sentinel) {
    return instance.valueAsString;
  } else {
    return '';
  }
}

/// A class to cache source loaded from the VM.
class _VmSourceCache {
  final String cacheDir;

  Map<String, String> _pathMappings = {};

  _VmSourceCache() : cacheDir = fs.join(fs.tmpdir, 'vm_cache');

  _VmSourceCache.withDir(this.cacheDir);

  String createRetrieveCachePath(String originalPath, String source) {
    if (!_pathMappings.containsKey(originalPath)) {
      List<String> safeNames = _createSafePathNames(originalPath);
      String filePath;
      if (safeNames.length == 2) {
        filePath = fs.join(cacheDir, safeNames[0], safeNames[1]);
      } else {
        filePath = fs.join(cacheDir, safeNames[0]);
      }
      _createFile(filePath, source);
      _pathMappings[originalPath] = filePath;
    }

    return _pathMappings[originalPath];
  }

  void _createFile(String filePath, String source) {
    new File.fromPath(filePath).writeSync(source);
  }

  /// Create a safe dir name and a safe file name based on the given file path or
  /// url.
  ///
  ///  - dart:isolate-patch/isolate_patch.dart
  ///  - /home/travis/build/flutter/bui...elease/gen/sky/bindings/Customhooks.dart
  ///  - dart:_builtin
  static List<String> _createSafePathNames(String path) {
    if (path.indexOf(':') > 1) {
      try {
        Uri uri = Uri.parse(path);
        String temp = uri.path;
        if (temp.contains('/')) {
          return [fs.dirname(temp), fs.basename(temp)];
        } else {
          return temp.contains('.') ? [temp] : [temp + '.dart'];
        }
      } catch (e) { }
    }

    if (path.indexOf('\\') != -1) {
      List<String> l = path.split('\\');
      if (l.length == 1) {
        return l;
      } else {
        return [l[l.length - 2], l[l.length - 1]];
      }
    }

    List<String> l = path.split('/');
    if (l.length == 1) {
      return l;
    } else {
      return [l[l.length - 2], l[l.length - 1]];
    }
  }
}
