library atom.chrome_debugger;

import 'dart:async';
import 'dart:html' show HttpRequest;

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart' as fs;
import 'package:atom/node/process.dart';
import 'package:atom/src/js.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';
import 'package:source_maps/source_maps.dart';
import 'package:source_maps/src/utils.dart';
import 'package:source_span/source_span.dart';

import '../analysis_server.dart';
import '../launch/launch.dart';
import '../state.dart';
import 'breakpoints.dart';
import 'chrome.dart';
import 'debugger.dart';
import 'evaluator.dart';
import 'model.dart';

final Logger _logger = new Logger('atom.chrome');

final RegExp extractSymbolKey = new RegExp(r'Symbol\((.+)\)');

const _verbose = false;

// TODO figure out how to set breakpoints them without needing a restart
// calling pause/resume ?
// TODO on user reload, should we remove all breakpoints and reset them?
// TODO put up message when pausing (running -> waiting to pause)
// TODO investigate why debug launch gets closed properly when restarting
//   but not serve launch
// TODO console + find in console
// TODO add continueToLocation
// TODO make scopes, exceptions and super more identifiable (UI)
// TODO fix hint being truncated at the right because italic
// TODO figure out why location is sometimes off near start and end of functions

const String _debuggerDdcParsing = 'dartlang.debuggerDdcParsing';

class ChromeDebugger {
  /// Establish a connection to a service protocol server at the given port.
  static Future<DebugConnection> connect(Launch launch, LaunchConfiguration configuration,
    String debugHost, String root, String htmlFile) {
    var cdp = new ChromeDebuggingProtocol();
    int maxTries = 10;
    return Future.doWhile(() async {
      try {
        if (maxTries-- == 0) {
          atom.notifications.addWarning("Coudn't connect to debugger at '$debugHost'.");
          return false;
        }
        var client = await cdp.connect(host: debugHost);
        await Future.wait([
          client.debugger.enable(),
          client.page.enable(),
          client.runtime.enable()
        ]);

        String fullPath =
            '${configuration.projectPath}/${configuration.shortResourceName}';
        UriResolver uriResolver = new UriResolver(root,
            translator: new WebUriTranslator(fs.fs.dirname(fullPath),
                prefix: '${Uri.parse(root)}/'),
            selfRefName: launch.project?.getSelfRefName(),
            projectPath: configuration.projectPath);

        ChromeConnection connection = new ChromeConnection(launch, client, uriResolver);
        var launchId = await connection.navigate('$root/$htmlFile');
        launch.addDebugConnection(connection);
        launch.pipeStdio('Launched ($launchId)\n');
        return false;
      } catch(e) {
        launch.pipeStdio('Launched failed, retrying\n');
        return new Future.delayed(new Duration(seconds: 1)).then((_) => true);
      }
    });
  }
}

class ChromeConnection extends DebugConnection {
  final ChromeDebugConnection chrome;
  final UriResolver uriResolver;

  final Completer completer;

  ChromeDebugIsolate _isolate;

  StreamController<DebugIsolate> _isolatePaused = new StreamController.broadcast();
  StreamController<DebugIsolate> _isolateResumed = new StreamController.broadcast();
  StreamController<List<DebugLibrary>> _librariesChanged = new StreamController.broadcast();

  StreamController<String> _dartMapUpdated = new StreamController.broadcast();
  StreamController<ChromeDebugBreakpoint> _breakpointsUpdated = new StreamController.broadcast();

  StreamSubscriptions subs = new StreamSubscriptions();

  /// Scripts and maps by scriptId
  Map<String, ScriptParsed> scripts = {};
  Map<String, Future<Mapping>> loadingMaps = {};
  Map<String, Mapping> maps = {};

  /// scripIds by file url
  Map<String, String> scriptIds = {};

  /// Etags by map file url
  Map<String, String> cachedTags = {};

  /// Librariaries, by url
  Map<String, DebugChromeLibrary> libraries = {};

  Map<AtomBreakpoint, ChromeDebugBreakpoint> breakpoints = {};

  DebugOption ddcParsing = new DdcParsingOption();
  List<DebugOption> get options => [ddcParsing];

  bool isPaused = false;

  ChromeConnection(Launch launch, this.chrome, this.uriResolver)
      : completer = new Completer(),
        super(launch) {
    launch.manager.onLaunchTerminated.listen((launch) {
      if (launch == this.launch) completer.complete();
    });

    chrome.debugger.scriptParsed((script) async {
      if (script.url == null || script.url.isEmpty) return;
      launch.pipeStdio('Script Parsed: ${script.url}\n');

      String previousScriptId = scriptIds[script.url];
      if (previousScriptId != null) {
        loadingMaps[script.scriptId] = loadingMaps.remove(previousScriptId);
        maps[script.scriptId] = maps.remove(previousScriptId);
        scripts.remove(previousScriptId);
      }

      scripts[script.scriptId] = script;
      scriptIds[script.url] = script.scriptId;
      if (script.sourceMapURL != null && script.sourceMapURL.isNotEmpty) {
        String mapFile = makeAbsolute(script.url, script.sourceMapURL);

        // minimize re-computing maps we have if the source hasn't changed.
        try {
          var request = await HttpRequest.request(mapFile, method: 'HEAD');
          var etag = request.responseHeaders['etag'];
          if (etag != null && cachedTags[mapFile] == etag) {
            launch.pipeStdio('  using cache $mapFile\n');
            return;
          }
          cachedTags[mapFile] = etag;
        } catch (e) {
          launch.pipeStdio('  file doesn\'t exist $mapFile\n');
          return;
        }

        // start load source map
        loadMaps() async {
          launch.pipeStdio('  fetching $mapFile\n');
          String text;
          try {
            text = await HttpRequest.getString(mapFile);
          } catch(e) {
            launch.pipeStdio('  error fetching $mapFile\n');
          }
          if (text == null) return null;
          Mapping map;
          try {
            map = parse(text);
          } catch(e) {
            launch.pipeStdio('  error parsing $mapFile\n');
          }
          if (map == null) return null;
          launch.pipeStdio('  parsing $mapFile\n');
          try {
            // create reverse map into separate for each .dart targets.
            return createMaps(script.scriptId, script.url, map);
          } catch(e) {
            launch.pipeStdio('  error creating reverse maps for ${script.url}.map\n');
          }
        }

        loadingMaps[script.scriptId] = loadMaps();
      }
    });
    chrome.debugger.scriptFailedToParse((script) {
      if (script.url == null || script.url.isEmpty) return;
      launch.pipeStdio('Script Parsed Failed: ${script.url}\n');
    });
    chrome.debugger.breakpointResolved((bkpt) {
      launch.pipeStdio('Breakpoint Resolved: $bkpt\n');
      // TODO add to breakpoints lists
    });

    chrome.debugger.paused((paused) {
      launch.pipeStdio('Pausing (${paused.reason}).\n');
      isPaused = true;
      _isolate = new ChromeDebugIsolate(this, this.chrome, paused);
      _isolatePaused.add(_isolate);
    });
    chrome.debugger.resumed(() {
      launch.pipeStdio('Resumed.\n');
      isPaused = false;
      _isolateResumed.add(_isolate);
    });

    subs.add(breakpointManager.onAdd.listen(addBreakpoint));
    subs.add(breakpointManager.onRemove.listen(removeBreakpoint));
    subs.add(breakpointManager.onBreakOnExceptionTypeChanged.listen((ExceptionBreakType val) {
      chrome.debugger.setPauseOnExceptions(exceptionTypes[val]).catchError((e) {
        launch.pipeStdio('Error setting exception mode ($e).\n');
      });
    }));

    subs.add(atom.config.onDidChange(_debuggerDdcParsing).listen((val) {
      // Force update
      if (isPaused && _isolate != null) {
        _isolate = new ChromeDebugIsolate(this, this.chrome, _isolate.paused);
        _isolatePaused.add(_isolate);
      }
    }));

    subs.add(_dartMapUpdated.stream.listen((map) {
      // find unresolved breakpoints ready for this map.
      breakpoints.values
          .where((b) => b != null && !b.resolved && b.uris.any((uri) => map == uri))
          .forEach((b) => resolveBreakpoint(b));
    }));

    subs.add(_breakpointsUpdated.stream.listen(resolveBreakpoint));
  }

  Future<DebugVariable> eval(EvalExpression expression) async {
    if (!isPaused || _isolate.frames == null) return null;
    // TODO figure out how to get selected frame
    DebugFrame frame = _isolate.frames.first;
    if (frame != null) {
      // we evaluate on this frame, then return a variable that will be
      // appended the the tooltip.
      String debugExpression = await new ChromeEvaluator(expression).eval();
      _logger.info('evaluateOnCallFrame($expression)');
      var result = await chrome.debugger.evaluateOnCallFrame(frame.id, debugExpression);
      RemoteObject object = result?.result ?? result?.exceptionDetails?.exception;
      if (object != null) {
        _logger.info('-> $object');
        return new ChromeEval(this, frame, debugExpression, object);
      }
    }

    return null;
  }

  Map<ExceptionBreakType, String> exceptionTypes = {
    ExceptionBreakType.all: 'all',
    ExceptionBreakType.uncaught: 'uncaught',
    ExceptionBreakType.none: 'none',
  };

  Future<String> navigate(String url) async {
    try {
      await chrome.debugger.setPauseOnExceptions(
          exceptionTypes[breakpointManager.breakOnExceptionType]);
    } catch(e) {
      launch.pipeStdio('Error setting exception mode ($e).\n');
    }
    try {
      await chrome.debugger.setAsyncCallStackDepth(16);
    } catch(e) {
      launch.pipeStdio('Error setting async call depth ($e).\n');
    }
    await installBreakpoints();
    return chrome.page.navigate(url);
  }

  // TODO handle .. and . ?
  static String makeAbsolute(String sourceUrl, String path) {
    if (!path.startsWith('http')) {
      Uri src = Uri.parse(sourceUrl);
      List<String> pathSegments = new List.from(src.pathSegments);
      pathSegments..removeLast()..add(path);
      path = Uri.decodeFull(src.replace(pathSegments: pathSegments).toString());
    }
    return path;
  }

  /// Create forward and reverse maps from the given source map.
  Mapping createMaps(String scriptId, String sourceUrl, Mapping map) {
    if (map is SingleMapping) {
      // TODO: rewrite for efficiency, creating forward and reverse mappings
      // as we read original map.
      Map<String, List<Entry>> entries = {};
      List<Entry> forwardEntries = [];
      for (var line in map.lines) {
        if (line.entries == null) continue;
        for (var entry in line.entries) {
          if (entry.sourceUrlId == null || entry.sourceUrlId < 0) continue;
          String destinationUrl = makeAbsolute(sourceUrl, map.urls[entry.sourceUrlId]);
          Entry newEntry = new Entry(
              new RevSourceLocation(entry.column, line.line, sourceUrl),
              new RevSourceLocation(entry.sourceColumn, entry.sourceLine, destinationUrl),
              entry.sourceNameId != null && entry.sourceNameId >= 0
                  ? map.names[entry.sourceNameId] : null);
          entries.putIfAbsent(destinationUrl, () => []).add(newEntry);

          Entry forwardEntry = new Entry(
              new RevSourceLocation(entry.sourceColumn, entry.sourceLine, destinationUrl),
              new RevSourceLocation(entry.column, line.line, sourceUrl),
              entry.sourceNameId != null && entry.sourceNameId >= 0
                  ? map.names[entry.sourceNameId] : null);
          forwardEntries.add(forwardEntry);
        }
      }
      // forward map
      Mapping forwardMap = new SingleMapping.fromEntries(forwardEntries, sourceUrl);
      maps[scriptId] = forwardMap;
      // backward maps
      entries.forEach((k, v) {
        k = makeAbsolute(sourceUrl, k);
        launch.pipeStdio('  adding reverse map for $k -> $sourceUrl\n');
        libraries[k] = new DebugChromeLibrary(this, k, new SingleMapping.fromEntries(v, k));
        _dartMapUpdated.add(k);
        _librariesChanged.add(new List<DebugLibrary>.from(libraries.values));
      });
      return forwardMap;
    }
    // Better than nothing?
    return map;
  }

  Future addBreakpoint(AtomBreakpoint atomBreakpoint) async {
    try {
      List<String> uris = await uriResolver.resolvePathToUris(atomBreakpoint.path);
      var breakpoint = new ChromeDebugBreakpoint(atomBreakpoint, uris);
      breakpoints[atomBreakpoint] = breakpoint;
      _breakpointsUpdated.add(breakpoint);
    } catch(e) {
      launch.pipeStdio(
          '  error resolving uri: ${atomBreakpoint.path}\n'
          '    ${e}\n');
    }
  }

  Future resolveBreakpoint(ChromeDebugBreakpoint breakpoint) {
    return Future.forEach(breakpoint.uris, (String uri) async {
      Mapping m = libraries[uri]?.mapping;
      if (m == null) return;

      SourceMapSpan span = SingleMappingProxy.spanFor(m,
          breakpoint.atomBreakpoint.line - 1,
          breakpoint.atomBreakpoint.column ?? 0);
      if (span == null) return;

      try {
        Breakpoint chromeBreakpoint =
            await setBreakpointByUrl(span.sourceUrl.toString(), span.start.line, span.start.column);
        if (chromeBreakpoint != null) {
          breakpoint.resolved = true;
          breakpoint.chromeBreakpoints.add(chromeBreakpoint);
        }
      } catch (e) {
        launch.pipeStdio('Fail to set breakpoint: ${breakpoint.atomBreakpoint}\n');
      }
    });
  }

  Future removeBreakpoint(AtomBreakpoint atomBreakpoint) {
    ChromeDebugBreakpoint breakpoint = breakpoints.remove(atomBreakpoint);
    if (breakpoint != null && breakpoint.resolved) {
      return Future.forEach(breakpoint.chromeBreakpoints, (Breakpoint chromeBreakpoint) {
        return chrome.debugger.removeBreakpoint(chromeBreakpoint.breakpointId)
            .catchError((e) {
          launch.pipeStdio('Error removing breakpoint:\n  $e\n');
        });
      });
    }
    return new Future.value();
  }

  Future installBreakpoints() {
    return Future.forEach(breakpointManager.breakpoints, (AtomBreakpoint atomBreakpoint) {
      if (breakpoints[atomBreakpoint] != null || !atomBreakpoint.fileExists()) {
        return null;
      }
      return addBreakpoint(atomBreakpoint);
    });
  }

  Future<Breakpoint> setBreakpointByUrl(String url, int line, int column) async {
    var bk = await chrome.debugger.setBreakpointByUrl(line, url: url, columnNumber: column);
    launch.pipeStdio('Breakpoint added: $bk\n');
    return bk;
  }

  void dispose() {
    subs.cancel();
    if (isAlive) terminate();
    chrome.close();
    uriResolver.dispose();
  }

  bool get isAlive => launch.isRunning;

  Stream<DebugIsolate> get onPaused => _isolatePaused.stream;
  Stream<DebugIsolate> get onResumed => _isolateResumed.stream;
  Stream<List<DebugLibrary>> get onLibrariesChanged => _librariesChanged.stream;

  Future get onTerminated => completer.future;

  Future resume() => chrome.debugger.resume();

  stepIn() {
    if (isPaused) {
      isPaused = false;
      chrome.debugger.stepInto();
    }
  }
  stepOut() {
    if (isPaused) {
      isPaused = false;
      chrome.debugger.stepOut();
    }
  }
  stepOver() {
    if (isPaused) {
      isPaused = false;
      chrome.debugger.stepOver();
    }
  }

  autoStepOver() => stepOver();

  stepOverAsyncSuspension() {}

  Future terminate() => launch.kill();
}

class DdcParsingOption extends DebugOption {
  String get label => 'Map stack to DDC output';

  bool get checked => atom.config.getValue(_debuggerDdcParsing);
  set checked(bool state) => atom.config.setValue(_debuggerDdcParsing, state);
}

class ChromeEvaluator extends Evaluator {

  ChromeEvaluator(EvalExpression expression) : super(expression);

  Future<String> mapReferenceIdentifier(bool first, int offset, String identifier) async {
    if (first) {
      HoverResult result = await analysisServer.getHover(expression.filePath, offset);
      if (result.hovers.isNotEmpty) {
        HoverInformation info = result.hovers.first;
        String kind = info.elementKind;
        if (kind == 'field') {
          return 'this.$identifier';
        } else if (kind == 'top level variable') {
          String library = _libraryName(info.containingLibraryPath ?? expression.filePath);
          return '$library.$identifier';
        }
      }
    }
    return identifier;
  }

  String _libraryName(String path) {
    path = new fs.File.fromPath(path).getBaseName();
    if (path.endsWith('.dart')) {
      return path.substring(0, path.length - 5);
    } else {
      return path;
    }
  }
}

class ChromeDebugBreakpoint {
  final AtomBreakpoint atomBreakpoint;
  final List<String> uris;

  List<Breakpoint> chromeBreakpoints = [];
  bool resolved = false;

  ChromeDebugBreakpoint(this.atomBreakpoint, this.uris);
}

class RevSourceLocation extends SourceLocation {
  RevSourceLocation(int column, int line, sourceUrl)
      : super(column, sourceUrl: sourceUrl, line: line);

  int compareTo(SourceLocation other) {
    int to = line - other.line;
    if (to == 0) to = column - other.column;
    return to;
  }
}

class SingleMappingProxy {
  /// Proxies SingleMapping and returns first span of a line if we
  /// don't know the column.
  ///
  /// Makes sense for reverse maps, because Atom doesn't have a column
  /// for the breakpoint.
  static SourceMapSpan spanFor(SingleMapping proxy, int line, int column,
      {Map<String, SourceFile> files, String uri}) {
    var entry = _findColumn(line, column, _findLine(proxy.lines, line));
    if (entry == null || entry.sourceUrlId == null) return null;
    return proxy.spanFor(line, entry.column, files: files, uri: uri);
  }

  static TargetEntry _findColumn(int line, int column, TargetLineEntry lineEntry) {
    if (lineEntry == null || lineEntry.entries.length == 0) return null;
    if (lineEntry.line != line) return lineEntry.entries.last;
    var entries = lineEntry.entries;
    int index = binarySearch(entries, (e) => e.column > column);
    return (index <= 0) ? entries.first : entries[index - 1];
  }

  static TargetLineEntry _findLine(List<TargetLineEntry> lines, int line) {
    int index = binarySearch(lines, (e) => e.line > line);
    return (index <= 0) ? null : lines[index - 1];
  }
}

class DebugChromeLibrary extends DebugLibrary {
  final ChromeConnection connection;
  final String uri;
  final Mapping mapping;

  String get id => uri;
  String get displayUri => Uri.parse(uri).path;
  String get name => '';

  bool get private => false;

  DebugChromeLibrary(this.connection, this.uri, this.mapping);

  int compareTo(other) {
    return displayUri.compareTo(other.displayUri);
  }

  DebugLocation get location => new ChromDebugLibraryLocation(this);
}

class ChromDebugLibraryLocation extends DebugLocation {
  final DebugChromeLibrary library;

  String get path => _resolvedPath ?? library.uri;

  int get line => 1;
  int get column => 1;
  String get displayPath => library.displayUri;

  bool resolved = false;

  String _resolvedPath;

  ChromDebugLibraryLocation(this.library);

  Future<DebugLocation> resolve() async {
    if (path != null) {
      try {
        _resolvedPath = await library.connection.uriResolver.resolveUriToPath(path);
        resolved = true;
      } catch(e) {
        _logger.warning('Failed to resolve: $path -> $e');
      }
    }
    return this;
  }

  String toString() => '${path}';
}

class ChromeDebugIsolate extends DebugIsolate {
  final ChromeConnection connection;
  final ChromeDebugConnection chrome;
  final Paused paused;

  List<DebugFrame> _frames;

  ChromeDebugIsolate(this.connection, this.chrome, this.paused) : super() {
    connection.isolates.add(this);
  }

  // TODO: add Web Workers / Service Workers as isolates
  String get name => 'main';

  /// Return a more human readable name for the Isolate.
  String get displayName => name;

  String get detail => paused.reason;

  bool get suspended => connection.isPaused;

  bool get hasFrames => frames != null && frames.isNotEmpty;

  bool get isInException => paused.reason == 'exception';

  RemoteObject get exception =>
      isInException ? new RemoteObject(paused.data, RemoteObjectType.exception) : null;

  List<DebugFrame> get frames {
    return _frames ??= []
        ..addAll(paused.callFrames?.map((frame) =>
            new ChromeDebugFrame(connection, exception, frame)) ?? [])
        // TODO id async frames in UI
        ..addAll(paused.asyncStackTrace?.callFrames?.map((frame) =>
            new ChromeDebugAsyncFrame(connection, frame)) ?? []);
  }

  List<DebugLibrary> get libraries =>
      new List<DebugLibrary>.from(connection.libraries.values);

  pause() => chrome.debugger.pause();

  Future resume() => connection.resume();
  stepIn() => connection.stepIn();
  stepOver() => connection.stepOver();
  stepOut() => connection.stepOut();
  stepOverAsyncSuspension() => connection.stepOverAsyncSuspension();
  autoStepOver() => connection.autoStepOver();
}

class ChromeDebugFrame extends DebugFrame {
  final ChromeConnection connection;
  final RemoteObject exception;
  final CallFrame frame;

  List<DebugVariable> _locals;

  String get id => frame.callFrameId;

  String get title =>
      frame.functionName != null && frame.functionName.isNotEmpty
          ? frame.functionName : 'anonymous';

  bool get isSystem => false;
  bool get isExceptionFrame => false;

  List<DebugVariable> get locals => _locals;

  DebugLocation get location =>
      new ChromeDebugLocation(connection, frame.location);

  ChromeDebugFrame(this.connection, this.exception, this.frame) : super();

  Future<List<DebugVariable>> resolveLocals() async {
    if (!connection.isPaused) return [];
    _locals = [];
    addException();
    await addThis();
    addScopes();
    addReturnValue();
    return _locals;
  }

  void addException() {
    if (exception != null) {
      _locals.add(new ChromeThis(connection, this, exception));
    }
  }

  Future addThis() async {
    if (frame?.self?.type == 'undefined') {
      try {
        var result = await connection.chrome.debugger.evaluateOnCallFrame(id, 'this');
        RemoteObject object = result?.result;
        if (object != null) {
          object = new RemoteObject(object.obj, RemoteObjectType.self);
          _locals.add(new ChromeThis(connection, this, object));
        }
      } catch(e) {
        _logger.info('problem getting missing this: $e');
      }
      return _locals;
    } else {
      _locals.add(new ChromeThis(connection, this, frame.self));
    }
  }

  void addScopes() {
    if (connection.ddcParsing.checked) {
      int i = 0;
      while (frame.scopeChain[i].name == frame.functionName) i++;
      // combine all starting scopes with the current frame name (if any).
      if (i > 0) {
        _locals.add(new ChromeScopes(connection, this, frame.scopeChain.sublist(0, i)));
      }
      for (; i < frame.scopeChain.length; i++) {
        _locals.add(new ChromeScope(connection, this, frame.scopeChain[i]));
      }
    } else {
      for (var property in frame.scopeChain) {
        _locals.add(new ChromeScope(connection, this, property));
      }
    }
  }

  void addReturnValue() {
    if (frame.returnValue != null) {
      _locals.add(new ChromeThis(connection, this, frame.returnValue));
    }
  }

  Future<String> eval(String expression) {
    // TODO (enable expression tab)
    // connection.debugger.evaluateOnCallFrame
    return new Future.value();
  }
}

class ChromeDebugAsyncFrame extends DebugFrame {
  final ChromeConnection connection;
  final RuntimeCallFrame frame;

  String get id => frame.location.toString();

  String get title =>
      frame.functionName != null && frame.functionName.isNotEmpty
          ? frame.functionName : 'anonymous';

  bool get isSystem => false;
  bool get isExceptionFrame => false;

  List<DebugVariable> get locals => [];
  DebugLocation get location => new ChromeDebugLocation(connection, frame.location);

  ChromeDebugAsyncFrame(this.connection, this.frame) : super();

  Future<List<DebugVariable>> resolveLocals() => new Future.value([]);
  Future<String> eval(String expression) => new Future.value();
}

abstract class ChromeDebugBaseVariable extends DebugVariable {
  final ChromeConnection connection;
  final ChromeDebugFrame frame;
  final ChromeDebugBaseVariable parent;

  RemoteObject get object;

  bool get isSymbol => false;

  ChromeDebugValue _value;
  DebugValue get value => _value ??= new ChromeDebugValue(connection, this, object);

  /// element in the chain to evaluate this field, i.e. this.field1.field2
  String get pathPart => name;

  ChromeDebugBaseVariable(this.connection, this.frame, [this.parent]);

  Future getChildren(bool own, Map<String, DebugVariable> children) {
    return Future.wait([getProperties(true, object), getProperties(false, object)])
        .then((properties) {
      properties.forEach((property) => addProperties(children, property));
    });
  }

  Future<Property> getProperties(bool own, RemoteObject object) {
    return connection.chrome.runtime.getProperties(object.objectId,
        ownProperties: own,
        accessorPropertiesOnly: !own,
        generatePreview: false);
  }

  void addProperties(Map<String, DebugVariable> children, Property property) {
    property.result.forEach((descriptor) {
      addProperty(children, descriptor);
    });
    property.internalProperties.forEach((descriptor) {
      addProperty(children, descriptor);
    });
  }

  void addProperty(Map<String, DebugVariable> children, PropertyDescriptor property) {
    String name = property.name;
    if (connection.ddcParsing.checked) {
      // Filter out symbols not defined on this object.
      if (property.symbol != null && !property.isOwn) {
        return;
      }
      // Rename __proto__ to super just to keep same 'lingo'.
      if (property.name == '__proto__') {
        name = 'super';
      }
      // Rename Symbol(a.b.c) to c, and let dedup do it's job below.
      if (extractSymbolKey.hasMatch(name)) {
        name = extractSymbolKey.firstMatch(name).group(1).split('.').last;
      }
    }
    // Filter out symbols functions, not a getter.
    if (property.symbol != null && property.value?.type == 'function') {
      return;
    }
    // Dedup by priority (isOwn for now, seems to cover known cases)
    bool add = false;
    if (children.containsKey(name)) {
      // Dedup by priority (isOwn for now, seems to cover known cases)
      ChromeDebugVariable variable = children[name];
      add = !variable.property.isOwn && property.isOwn;
    } else {
      add = true;
    }
    if (add) {
      children[name] = new ChromeDebugVariable(connection, frame,
          this, property, rename: name);
    }
  }
}

const Map<RemoteObjectType, String> _metaLabels = const {
  RemoteObjectType.self: 'this',
  RemoteObjectType.exception: 'exception',
  RemoteObjectType.scope: 'scope',
  RemoteObjectType.setter: 'set',
  RemoteObjectType.getter: 'get',
  RemoteObjectType.value: 'value',
  RemoteObjectType.returnValue: 'return',
  RemoteObjectType.result: 'result',
  RemoteObjectType.symbol: 'symbol'
};

class ChromeThis extends ChromeDebugBaseVariable {
  final RemoteObject object;

  String get name => _metaLabels[object.meta];

  String get pathPart => 'this';

  ChromeThis(ChromeConnection connection, ChromeDebugFrame frame, this.object)
      : super(connection, frame);
}

class ChromeEval extends ChromeDebugBaseVariable {
  final RemoteObject object;
  final String name;

  ChromeEval(ChromeConnection connection, ChromeDebugFrame frame, this.name, this.object)
      : super(connection, frame);
}

class ChromeScope extends ChromeDebugBaseVariable {
  final Scope scope;

  RemoteObject get object => scope.object;

  // We have multiple scope with same name.
  String get id => '$name.${scope.startLocation}';

  String get name => scope.name ?? scope.type;

  // Scopes are not referenceable.
  String get pathPart => null;

  ChromeScope(ChromeConnection connection, ChromeDebugFrame frame, this.scope)
      : super(connection, frame);
}

class ChromeScopes extends ChromeDebugBaseVariable {
  final List<Scope> scopes;

  RemoteObject get object => scopes.first.object;

  // We have multiple scope with same name - use last for re-expending in MTree.
  String get id => '$name.${scopes.last.startLocation}';

  String get name => 'local';

  // Scopes are not referenceable.
  String get pathPart => null;

  ChromeScopes(ChromeConnection connection, ChromeDebugFrame frame, this.scopes)
      : super(connection, frame);

  Future getChildren(bool own, Map<String, DebugVariable> children) {
    // Respect order of scopes.
    return Future.forEach(scopes, (scope) {
      return getProperties(true, scope.object).then((property) =>
          addProperties(children, property));
    });
  }

  void addProperty(Map<String, DebugVariable> children, PropertyDescriptor property) {
    // Dedup by respect order of scopes, i.e. fields hiding other fields.
    if (!children.containsKey(property.name)) {
      children[property.name] = new ChromeDebugVariable(connection, frame,
          this, property);
    }
  }
}

class ChromeDebugVariable extends ChromeDebugBaseVariable {
  final PropertyDescriptor property;
  final String rename;

  bool get isSymbol => property.symbol != null;

  RemoteObject get object => property.value ?? property.getFunction;

  String get name => rename ?? property.name;

  ChromeDebugVariable(ChromeConnection connection, ChromeDebugFrame frame,
      ChromeDebugBaseVariable parent, this.property, {this.rename})
      : super(connection, frame, parent);

  String toString() => '${jsObjectToDart(property.obj)}';
}

class ChromeDebugValue extends DebugValue {
  final ChromeConnection connection;
  final ChromeDebugBaseVariable variable;
  final RemoteObject value;
  final bool replaceValueOnEval;

  Map<String, DebugVariable> children;

  ChromeDebugFrame get frame => variable.frame;

  String get className =>
      value == null ? 'Null' :
      value.className != null ? value.className :
      value.type != null && value.subtype != null ?
          "${value.type}.${value.subtype}" : value.type;

  String get valueAsString =>
      value?.value ?? value?.description ?? value?.unserializableValue;

  bool get isString => value?.type == 'string';
  bool get isPlainInstance => !isPrimitive;

  bool get isPrimitive => !isList && !isMap;
  bool get isList => value?.subtype == 'array' && value?.objectId != null;
  bool get isMap => !isList && !isSymbol && value?.objectId != null;

  bool get isSymbol => value?.type == 'symbol';

  bool get valueIsTruncated => false;

  String get hint {
    if (isString) {
      // We choose not to escape double quotes here; it doesn't work well visually.
      String str = valueAsString;
      return valueIsTruncated ? '"$str…' : '"$str"';
    } else if (isSymbol) {
      return value?.description;
    } else if (value?.meta == RemoteObjectType.getter) {
      return 'get...';
    } else if (isList || isMap || isPlainInstance) {
      return className;
    } else {
      return valueAsString;
    }
  }

  // We don't know this until getChildren() is called so we use hint instead.
  // Even after getChildren() we would have to count elements that are actual
  // values.
  int get itemsLength => null;

  // Warning: value can be null.
  ChromeDebugValue(this.connection, this.variable, this.value, {this.replaceValueOnEval: false});

  Future<List<DebugVariable>> getChildren() async {
    if (!connection.isPaused) return [];
    children = {};
    await variable.getChildren(true, children);
    return new List.from(children.values)..sort(variableSorter);
  }

  // Sort __ / super to the end
  int variableSorter(DebugVariable a, DebugVariable b) {
    if (a.name == b.name) return 0;
    if (a.name.startsWith('_')) {
      if (b.name.startsWith('_')) return a.name.compareTo(b.name);
      return 1;
    } else if (b.name.startsWith('_')) {
      return -1;
    }
    if (a.name == 'super') return 1;
    if (b.name == 'super') return -1;
    return a.name.compareTo(b.name);
  }

  Iterable<String> get pathParts {
    List<String> tokens = [];
    for (var chain = variable; chain != null; chain = chain.parent) {
      if (chain.pathPart == null ||
          chain.pathPart == '__proto__' || chain.pathPart == 'super') {
        continue;
      }
      tokens.add(chain.pathPart);
    }
    return tokens.reversed;
  }

  String get path => pathParts.join('.');

  String get symbolEval {
    String lookup = '';
    String name = variable is ChromeDebugVariable ?
        (variable as ChromeDebugVariable).property.name : variable.name;
    Match m = extractSymbolKey.firstMatch(name);
    if (m != null) lookup = '[${m.group(1)}]';
    List<String> root = pathParts;
    return '${root.take(root.length - 1).join('.')}$lookup';
  }

  Future<DebugValue> invokeToString() async {
    if (value?.meta == RemoteObjectType.getter) {
      String expression = variable.isSymbol ? symbolEval: path;
      _logger.info('evaluateOnCallFrame($expression)');
      var result = await connection.chrome.debugger.evaluateOnCallFrame(frame.id, expression);
      RemoteObject object = result?.result ?? result?.exceptionDetails?.exception;
      _logger.info('-> $object');
      ChromeDebugValue value = object != null
          ? new ChromeDebugValue(connection, variable, object, replaceValueOnEval: true)
          : this;
      variable._value = value;
      return value;
    }
    return this;
  }

  String toString() => value?.toString(' ');
}

class ChromeDebugLocation extends DebugLocation {
  final ChromeConnection connection;
  final Location location;

  SourceMapSpan _span;
  String _resolvedPath;

  /// A file path.
  String get path => _resolvedPath ?? displayPath;

  /// 1-based line number.
  int get line => _span == null ? 0 : _span.start.line + 1;

  /// 1-based column number.
  int get column => _span == null ? 0 : _span.start.column + 1;

  /// A display file path.
  String get displayPath => _span == null
      ? connection.scripts[location.scriptId]?.url
      : _span.start.sourceUrl.toString();

  bool resolved = false;

  ChromeDebugLocation(this.connection, this.location) {
    var map = connection.maps[location.scriptId];
    _span = map?.spanFor(location.lineNumber, location.columnNumber);
  }

  Future<DebugLocation> resolve() async {
    // TOOD catch error and don't try again
    if (!resolved && connection.loadingMaps[location.scriptId] != null) {
      var map = await connection.loadingMaps[location.scriptId];
      _span = map?.spanFor(location.lineNumber, location.columnNumber);
      if (_span != null) await _resolvePath();
    }
    return this;
  }

  Future _resolvePath() async {
    Uri sourceUrl = _span?.start?.sourceUrl;
    if (sourceUrl != null) {
      try {
        _resolvedPath = await connection.uriResolver.resolveUriToPath('$sourceUrl');
        resolved = true;
      } catch(e) {
        _logger.warning('Failed to resolve: $sourceUrl -> $e');
      }
    }
    return this;
  }
}

class WebUriTranslator implements UriTranslator {
  static const _packagesPrefix = 'packages/';
  static const _packagePrefix = 'package:';

  final String root;
  final String prefix;

  String _rootPrefix;

  WebUriTranslator(this.root, {this.prefix: 'http://localhost:8084/'}) {
    _rootPrefix = new Uri.directory(root, windows: isWindows).toString();
  }

  String targetToClient(String str) {
    if (str.startsWith(prefix)) {
      str = str.substring(prefix.length);
      if (str.startsWith(_packagesPrefix)) {
        // Convert packages/ prefix to package: one.
        return _packagePrefix + str.substring(_packagesPrefix.length);
      } else {
        // Return files relative to the starting project.
        return '${_rootPrefix}${str}';
      }
    } else {
      return '${_rootPrefix}${str}';
    }
  }

  String clientToTarget(String str) {
    if (str.startsWith(_packagePrefix)) {
      // Convert package: prefix to packages/ one.
      return prefix + _packagesPrefix + str.substring(_packagePrefix.length);
    } else if (str.startsWith(_rootPrefix)) {
      // Convert file:///foo/bar/lib/main.dart to http://.../lib/main.dart.
      return prefix + str.substring(_rootPrefix.length);
    } else if (str.startsWith('file://')) {
      // We are trying to add a breakpoint on a package not a root project
      var uri = Uri.parse(str);
      var segments = uri.pathSegments;
      int lib = segments.indexOf('lib');
      if (lib > 0) {
        return prefix + _packagesPrefix + segments[lib - 1] + '/' + segments.skip(lib + 1).join('/');
      }
    }
    return str;
  }
}
