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
import 'utils.dart';

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
  StreamController<DebugIsolate> _isolatePaused = new StreamController.broadcast();
  StreamController<DebugIsolate> _isolateResumed = new StreamController.broadcast();

  StreamSubscriptions subs = new StreamSubscriptions();
  UriResolver uriResolver;

  bool stdoutSupported = true;
  bool stderrSupported = true;

  int _nextIsolateId = 1;

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

  Stream<DebugIsolate> get onPaused => _isolatePaused.stream;
  Stream<DebugIsolate> get onResumed => _isolateResumed.stream;

  // TODO: The UI should be in charge of servicing the connection level flow
  // control commands.
  DebugIsolate get _selectedIsolate => isolates.selection;

  Future resume() => _selectedIsolate?.resume();
  stepIn() => _selectedIsolate?.stepIn();
  stepOver() => _selectedIsolate?.stepOver();
  stepOut() => _selectedIsolate?.stepOut();

  Future terminate() => launch.kill();

  Future get onTerminated => completer.future;

  ObservatoryIsolate _getIsolate(IsolateRef ref) => _isolateMap[ref.id];

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
      String dart = vm.version;
      if (dart.contains(' ')) dart = dart.substring(0, dart.indexOf(' '));
      metadata.value = '${vm.targetCPU} • ${vm.hostCPU} • Dart ${dart}';
      _logger.info('Connected to ${metadata.value}');
      _registerNewIsolates(vm.isolates);
    });
  }

  Future _installBreakpoints(IsolateRef isolate) {
    Map<AtomBreakpoint, Breakpoint> _bps = {};

    subs.add(breakpointManager.onAdd.listen((bp) {
      uriResolver.resolvePathToUri(bp.path).then((List<String> uris) {
        // TODO: Use both returned values.
        return service.addBreakpointWithScriptUri(
            isolate.id, uris.first, bp.line, column: bp.column);
      }).then((Breakpoint vmBreakpoint) {
        _bps[bp] = vmBreakpoint;
      }).catchError((e) {
        // ignore
      });
    }));

    subs.add(breakpointManager.onRemove.listen((bp) {
      Breakpoint vmBreakpoint = _bps[bp];
      if (vmBreakpoint != null) {
        service.removeBreakpoint(isolate.id, vmBreakpoint.id);
      }
    }));

    // TODO: Run these in parallel.
    // TODO: Need to handle self-references and editor breakpoints multiplexed
    // over several VM breakpoints.
    return Future.forEach(breakpointManager.breakpoints, (AtomBreakpoint bp) {
      return uriResolver.resolvePathToUri(bp.path).then((List<String> uris) {
        // TODO: Use both returned values.
        return service.addBreakpointWithScriptUri(
            isolate.id, uris.first, bp.line, column: bp.column);
      }).then((Breakpoint vmBreakpoint) {
        _bps[bp] = vmBreakpoint;
      }).catchError((e) {
        // ignore
      });
    }).then((_) {
      return service.setExceptionPauseMode(
          isolate.id, ExceptionPauseMode.kUnhandled);
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
        // TODO: There's a race condition here with setting breakpoints; use a
        // Completer when registering isolates.
        _getIsolate(ref)?._performInitialResume();
        break;
      case EventKind.kPauseExit:
      case EventKind.kPauseBreakpoint:
      case EventKind.kPauseInterrupted:
      case EventKind.kPauseException:
        ObservatoryIsolate isolate = _getIsolate(ref);

        // TODO:
        if (event.exception != null) {
          launch.pipeStdio('exception: ${_refToString(event.exception)}\n',
              error: true);
        }

        isolate._populateFrames().then((_) {
          isolate._suspend(true);
        });
        break;
      case EventKind.kResume:
        _getIsolate(ref)?._suspend(false);
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
  //  - create
  //  - get meta data
  //  - install breakpoints
  //  - exception pause mode
  //  - resume from pause

  Future<ObservatoryIsolate> _registerNewIsolate(IsolateRef ref) {
    if (_isolateMap.containsKey(ref.id)) return new Future.value(_isolateMap[ref.id]);

    ObservatoryIsolate isolate = new ObservatoryIsolate._(this, service, ref);
    _isolateMap[ref.id] = isolate;
    isolates.add(isolate);

    return _installBreakpoints(ref).then((_) {
      // Get isolate metadata.
      return isolate._updateIsolateInfo();
    }).then((_) {
      if (isolate.isolate.pauseEvent.kind == EventKind.kPauseStart) {
        isolate._performInitialResume();
      }
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

  Future _updateIsolateMetadata(IsolateRef ref) {
    ObservatoryIsolate isolate = _isolateMap[ref.id];

    if (isolate == null) {
      return _registerNewIsolate(ref);
    } else {
      // Update the libraries list for the isolate.
      return isolate._updateIsolateInfo();
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
  final IsolateRef isolateRef;

  Isolate isolate;
  ScriptManager scriptManager;

  bool suspended = false;
  bool _didInitialResume = false;
  String _detail;

  ObservatoryIsolate._(this.connection, this.service, this.isolateRef) {
    scriptManager = new ScriptManager(service, this);
    _detail = '#${connection._nextIsolateId++}';
  }

  String get name => isolateRef.name;

  String get detail => _detail;

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

    suspended = value;

    if (value) {
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

  Future<ObservatoryIsolate> _updateIsolateInfo() {
    return service.getIsolate(isolateRef.id).then((Isolate isolate) {
      // TODO: Update the state info.

      this.isolate = isolate;

      return this;
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
          frame.vars.map((v) => new ObservatoryVariable(this, v))
        );
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
    if (!_didInitialResume) {
      _didInitialResume = true;
      resume();
    }
  }
}

class ObservatoryFrame extends DebugFrame {
  final ObservatoryIsolate isolate;
  final Frame frame;

  List<DebugVariable> locals;

  ObservatoryLocation _location;

  ObservatoryFrame(this.isolate, this.frame);

  String get title => printFunctionName(frame.function);

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
  final ObservatoryIsolate _isolate;
  final BoundVariable _variable;
  final DebugValue value;

  ObservatoryVariable(ObservatoryIsolate isolate, BoundVariable variable) :
    _isolate = isolate, _variable = variable, value = _createValue(isolate, variable);

  String get name => _variable.name;

  static DebugValue _createValue(ObservatoryIsolate isolate, BoundVariable variable) {
    if (variable.value is InstanceRef) {
      return new ObservatoryValue(isolate, variable.value);
    } else if (variable.value is Sentinel) {
      return new SentinelDebugValue(variable.value);
    } else {
      return null;
    }
  }
}

class ObservatoryFieldVariable extends DebugVariable {
  final ObservatoryIsolate _isolate;
  final BoundField _field;
  final DebugValue value;

  ObservatoryFieldVariable(ObservatoryIsolate isolate, BoundField field) :
    _isolate = isolate, _field = field, value = _createValue(isolate, field);

  String get name => _field.decl.name;

  static DebugValue _createValue(ObservatoryIsolate isolate, BoundField field) {
    if (field.value is InstanceRef) {
      return new ObservatoryValue(isolate, field.value);
    } else if (field.value is Sentinel) {
      return new SentinelDebugValue(field.value);
    } else {
      return null;
    }
  }
}

class ObservatoryValue extends DebugValue {
  final ObservatoryIsolate isolate;
  final InstanceRef value;

  ObservatoryValue(this.isolate, this.value);

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
    return isolate.service.getObject(isolate.id, value.id).then((ret) {
      if (ret is Instance) {
        // TODO: Handle arrays and other strange types.
        return ret.fields.map((BoundField field) {
          return new ObservatoryFieldVariable(isolate, field);
        });
      } else {
        return [];
      }
    });
  }

  // TODO: handle truncated
  String get valueAsString => value.valueAsString;
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

  Future<List<DebugVariable>> getChildren() {
    return new Future.value([]);
  }

  String get valueAsString => sentenial.valueAsString;
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

  bool get isSystem => location.script.uri.startsWith('dart:');

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
