library atom.chrome;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/node.dart';
import 'package:atom/src/js.dart';

Map _c(Map params) {
  Map clean = {};
  params.forEach((k, v) {
    if (v != null) clean[k] = v;
  });
  return clean;
}

class ChromeDebuggingProtocol extends ProxyHolder {
  ChromeDebuggingProtocol() : super(require('chrome-remote-interface'));

  Future<ChromeDebugConnection> connect({String host: 'localhost:9222', bool secure: false}) {
    Uri uri = Uri.parse(host);
    return promiseToFuture((obj as JsFunction)
        .apply(jsify([{'host': uri.host, 'port': uri.port, 'secure': secure}])))
            .then((client) => new ChromeDebugConnection(client));
  }
}

class ChromeDebugConnection extends ProxyHolder {
  ChromePage _page;
  ChromeNetwork _network;
  ChromeDebugger _debugger;
  ChromeRuntime _runtime;

  ChromeDebugConnection(JsObject obj) : super(obj);

  ChromePage get page => _page ??= new ChromePage(obj['Page']);
  ChromeNetwork get network => _network ??= new ChromeNetwork(obj['Network']);
  ChromeDebugger get debugger => _debugger ??= new ChromeDebugger(obj['Debugger']);
  ChromeRuntime get runtime => _runtime ??= new ChromeRuntime(obj['Runtime']);


  void close() => invoke('close');
}

class ChromeNetwork extends ProxyHolder {

  ChromeNetwork(JsObject obj) : super(obj);

  Future enable() => promiseToFuture(invoke('enable'));
  Future disable() => promiseToFuture(invoke('disable'));

  void requestWillBeSent(callback) =>
      invoke('requestWillBeSent', callback);
}

class ChromePage extends ProxyHolder {

  ChromePage(JsObject obj) : super(obj);

  Future enable() => promiseToFuture(invoke('enable'));
  Future disable() => promiseToFuture(invoke('disable'));

  Future reload({bool ignoreCache, String scriptToEvaluateOnLoad}) =>
      promiseToFuture(invoke('reload', _c({
        'ignoreCache': ignoreCache,
        'scriptToEvaluateOnLoad': scriptToEvaluateOnLoad})));
  Future<String> navigate(String url) =>
      promiseToFuture(invoke('navigate', {
        'url': url})).then((obj) => obj['frameId']);
}

class ChromeDebugger extends ProxyHolder {

  ChromeDebugger(JsObject obj) : super(obj);

  Future enable() => promiseToFuture(invoke('enable'));
  Future disable() => promiseToFuture(invoke('disable'));

  /// Activates / deactivates all breakpoints on the page.
  Future setBreakpointsActive(bool active) =>
      promiseToFuture(invoke('setBreakpointsActive', {'active': active}));

  /// Makes page not interrupt on any pauses (breakpoint, exception,
  /// dom exception etc).
  Future setSkipAllPauses(bool skip) =>
      promiseToFuture(invoke('setSkipAllPauses', {'skip': skip}));

  /// Sets JavaScript breakpoint at given location specified either by URL or
  /// URL regex. Once this command is issued, all existing parsed scripts will
  /// have breakpoints resolved and returned in locations property.
  /// Further matching script parsing will result in subsequent
  /// breakpointResolved events issued. This logical breakpoint will survive
  /// page reloads.
  ///
  /// [lineNumber]: Line number to set breakpoint at.
  /// [url]: URL of the resources to set breakpoint on.
  /// [urlRegex]: Regex pattern for the URLs of the resources to set breakpoints
  ///   on. Either url or urlRegex must be specified.
  /// [columnNumber]: Offset in the line to set breakpoint at.
  /// [condition]: Expression to use as a breakpoint condition. When specified,
  ///   debugger will only stop on the breakpoint if this expression evaluates
  ///   to true.
  Future<Breakpoint> setBreakpointByUrl(int lineNumber,
      {String url, String urlRegex, int columnNumber, String condition}) {
    return promiseToFuture(invoke('setBreakpointByUrl', _c({
      'lineNumber': lineNumber,
      'url': url,
      'urlRegex': urlRegex,
      'columnNumber': columnNumber,
      'condition': condition
    }))).then((obj) => new Breakpoint.setBreakpointByUrl(obj));
  }

  /// Sets JavaScript breakpoint at a given location.
  /// condition: Expression to use as a breakpoint condition. When specified,
  /// debugger will only stop on the breakpoint if this expression evaluates
  /// to true.
  ///
  /// [location]: Location to set breakpoint in.
  /// [condition]: Expression to use as a breakpoint condition. When specified,
  ///   debugger will only stop on the breakpoint if this expression evaluates
  ///   to true.
  Future<Breakpoint> setBreakpoint(Location location, {String condition}) {
    return promiseToFuture(invoke('setBreakpoint', _c({
      'location': location.toMap(),
      'condition': condition
    }))).then((obj) => new Breakpoint.setBreakpoint(obj));
  }

  /// Removes JavaScript breakpoint.
  Future removeBreakpoint(String breakpointId) =>
      promiseToFuture(invoke('removeBreakpoint', {'breakpointId': breakpointId}));

  /// Continues execution until specific location is reached.
  ///
  /// [location]: Location to continue to.
  Future continueToLocation(Location location) =>
      promiseToFuture(invoke('location', location.toMap()));

  /// Steps over the statement.
  Future stepOver() => promiseToFuture(invoke('stepOver'));

  /// Steps into the function call.
  Future stepInto() => promiseToFuture(invoke('stepInto'));

  /// Steps out of the function call.
  Future stepOut() => promiseToFuture(invoke('stepOut'));

  /// Stops on the next JavaScript statement.
  Future pause() => promiseToFuture(invoke('pause'));

  /// Resumes JavaScript execution.
  Future resume() => promiseToFuture(invoke('resume'));

  /// Edits JavaScript source live.
  ///
  /// [scriptId]: Id of the script to edit.
  /// [scriptSource]: New content of the script.
  /// [dryRun]: If true the change will not actually be applied. Dry run may be
  ///   used to get result description without actually modifying the code.
  Future<Breakpoint> setScriptSource(String scriptId, String scriptSource,
      {bool dryRun}) {
    return promiseToFuture(invoke('setScriptSource', _c({
      'scriptId': scriptId,
      'scriptSource': scriptSource,
      'dryRun': dryRun
    }))).then((obj) => new Breakpoint.setBreakpoint(obj));
  }

  /// Restarts particular call frame from the beginning.
  ///
  /// [callFrameId] Call frame identifier to evaluate on.
  Future<RestartFrame> restartFrame(String callFrameId) {
    return promiseToFuture(invoke('restartFrame', {
      'callFrameId': callFrameId
    })).then((obj) => new RestartFrame(obj));
  }

  /// Returns source for the script with given id.
  ///
  /// [scriptId]: Id of the script to get source for.
  /// returns: Script source.
  Future<String> getScriptSource(String scriptId) {
    return promiseToFuture(invoke('getScriptSource', {
      'scriptId': scriptId
    })).then((obj) => obj['scriptSource']);
  }

  /// Defines pause on exceptions state. Can be set to stop on all exceptions,
  /// uncaught exceptions or no exceptions. Initial pause on exceptions state
  /// is none.
  ///
  /// [state]: Pause on exceptions mode. Allowed values: none, uncaught, all.
  Future<String> setPauseOnExceptions(String state) =>
      promiseToFuture(invoke('setPauseOnExceptions', {'state': state}));

  /// Evaluates expression on a given call frame.
  ///
  /// [callFrameId]: Call frame identifier to evaluate on.
  /// [expression]: Expression to evaluate.
  /// [objectGroup]: String object group name to put result into (allows rapid
  ///   releasing resulting object handles using releaseObjectGroup).
  /// [includeCommandLineAPI]: Specifies whether command line API should be
  ///   available to the evaluated expression, defaults to false.
  /// [silent]: In silent mode exceptions thrown during evaluation are not
  ///   reported and do not pause execution. Overrides setPauseOnException
  ///   state.
  /// [returnByValue]: Whether the result is expected to be a JSON object that
  ///   should be sent by value.
  /// [generatePreview]: Whether preview should be generated for the result.
  ///   EXPERIMENTAL
  Future<EvaluateOn> evaluateOnCallFrame(String callFrameId, String expression,
      {String objectGroup, bool includeCommandLineAPI, bool silent,
      bool returnByValue, bool generatePreview}) {
    return promiseToFuture(invoke('evaluateOnCallFrame', _c({
      'callFrameId': callFrameId,
      'expression': expression,
      'objectGroup': objectGroup,
      'includeCommandLineAPI': includeCommandLineAPI,
      'silent': silent,
      'returnByValue': returnByValue,
      'generatePreview': generatePreview
    }))).then((obj) => new EvaluateOn(obj));
  }

  /// Changes value of variable in a callframe.
  /// Object-based scopes are not supported and must be mutated manually.
  ///
  /// [scopeNumber]: 0-based number of scope as was listed in scope chain.
  ///   Only 'local', 'closure' and 'catch' scope types are allowed. Other
  ///   scopes could be manipulated manually.
  /// [variableName]: Variable name.
  /// [newValue]: New variable value.
  /// [callFrameId]: Id of callframe that holds variable.
  Future<String> setVariableValue(int scopeNumber, String variableName,
      CallArgument newValue, String callFrameId) {
    return promiseToFuture(invoke('setVariableValue', {
      'scopeNumber': scopeNumber,
      'variableName': variableName,
      'newValue': newValue,
      'callFrameId': callFrameId
    }));
  }

  /// Enables or disables async call stacks tracking.
  ///
  /// [maxDepth]: Maximum depth of async call stacks. Setting to 0 will
  ///   effectively disable collecting async call stacks (default).
  Future<String> setAsyncCallStackDepth(int maxDepth) =>
      promiseToFuture(invoke('setAsyncCallStackDepth', {'maxDepth': maxDepth}));

  // Events

  void scriptParsed(void callback(ScriptParsed a)) =>
      invoke('scriptParsed', (obj) => callback(new ScriptParsed(obj)));

  void scriptFailedToParse(void callback(ScriptParsed s)) =>
      invoke('scriptFailedToParse', (obj) => callback(new ScriptParsed(obj)));

  /// Fired when breakpoint is resolved to an actual script and location.
  void breakpointResolved(void callback(Breakpoint b)) =>
      invoke('breakpointResolved', (obj) => callback(new Breakpoint.breakpointResolved(obj)));

  /// Fired when the virtual machine stopped on breakpoint or exception or any
  /// other stop criteria.
  void paused(void callback(Paused p)) =>
      invoke('paused', (obj) => callback(new Paused(obj)));

  /// Fired when the virtual machine resumed execution.
  void resumed(void callback()) => invoke('resumed', (_) => callback());
}

class ChromeRuntime extends ProxyHolder {

  ChromeRuntime(JsObject obj) : super(obj);

  Future enable() => promiseToFuture(invoke('enable'));
  Future disable() => promiseToFuture(invoke('disable'));

  /// Returns properties of a given object. Object group of the result is
  /// inherited from the target object.
  /// [objectId]: Identifier of the object to return properties for.
  ///
  /// [ownProperties]: If true, returns properties belonging only to the
  ///   element itself, not to its prototype chain.
  /// [accessorPropertiesOnly]: If true, returns accessor properties
  ///   (with getter/setter) only; internal properties are not returned
  ///   either. EXPERIMENTAL
  /// [generatePreview]: Whether preview should be generated for the results.
  ///   EXPERIMENTAL
  Future<Property> getProperties(String objectId, {bool ownProperties,
      bool accessorPropertiesOnly, bool generatePreview}) {
    return promiseToFuture(invoke('getProperties', _c({
      'objectId': objectId,
      'ownProperties': ownProperties,
      'accessorPropertiesOnly': accessorPropertiesOnly,
      'generatePreview': generatePreview
    }))).then((obj) => new Property(obj));
  }
}

class Paused extends ProxyHolder {

  Paused(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "PAUSED: $reason\n"
      "${indent}data: ${jsObjectToDart(data)}\n"
      "${indent}bk: $hitBreakpoints\n"
      "${indent}fr: ${callFrames.map((f) => f.toString(indent + '  '))}\n"
      "${indent}as: ${asyncStackTrace?.toString(indent + '  ')}";

  /// Call stack the virtual machine stopped on.
  List<CallFrame> get callFrames =>
      obj['callFrames']?.map((obj) => new CallFrame(obj))?.toList() ?? [];

  /// Pause reason. Allowed values: XHR, DOM, EventListener, exception, assert,
  /// debugCommand, promiseRejection, other.
  String get reason => obj['reason'];

  /// Object containing break-specific auxiliary properties.
  JsObject get data => obj['data'];

  /// Hit breakpoints IDs
  List<String> get hitBreakpoints => obj['hitBreakpoints'];

  /// Async stack trace, if any.
  StackTrace get asyncStackTrace => obj['asyncStackTrace'] == null
      ? null : new StackTrace(obj['asyncStackTrace']);
}

class ScriptSource extends ProxyHolder {

  ScriptSource(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "SOURCE: $stackChanged\n"
      "${indent}fr: ${callFrames.map((f) => f.toString(indent + '  '))}\n"
      "${indent}as: ${asyncStackTrace?.toString(indent + '  ')}\n"
      "${indent}exp: ${exceptionDetails?.toString(indent + '  ')}";

  /// New stack trace in case editing has happened while VM was stopped.
  List<CallFrame> get callFrames =>
      obj['callFrames']?.map((obj) => new CallFrame(obj))?.toList() ?? [];

  /// Whether current call stack was modified after applying the changes.
  bool get stackChanged => obj['stackChanged'] == true;

  /// Async stack trace, if any.
  StackTrace get asyncStackTrace => obj['asyncStackTrace'] == null
      ? null : new StackTrace(obj['asyncStackTrace']);

  /// Exception details if any.
  ExceptionDetails get exceptionDetails => obj['exceptionDetails'] == null
      ? null : new ExceptionDetails(obj['exceptionDetails']);
}

class RestartFrame extends ProxyHolder {

  RestartFrame(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "RESTART:\n"
      "${indent}fr: ${callFrames.map((f) => f.toString(indent + '  '))}\n"
      "${indent}as: ${asyncStackTrace?.toString(indent + '  ')}";

  /// New stack trace.
  List<CallFrame> get callFrames =>
      obj['callFrames']?.map((obj) => new CallFrame(obj))?.toList() ?? [];

  /// Async stack trace, if any.
  StackTrace get asyncStackTrace => obj['asyncStackTrace'] == null
      ? null : new StackTrace(obj['asyncStackTrace']);
}

class EvaluateOn extends ProxyHolder {

  EvaluateOn(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "EVAL: ${result?.toString(indent + '  ')}\n"
      "${indent}exp: ${exceptionDetails?.toString(indent + '  ')}";

  /// Object wrapper for the evaluation result.
  RemoteObject get result => obj['result'] == null
      ? null : new RemoteObject(obj['result'], RemoteObjectType.result);

  /// Exception details.
  ExceptionDetails get exceptionDetails => obj['exceptionDetails'] == null
      ? null : new ExceptionDetails(obj['exceptionDetails']);
}

/// JavaScript call frame. Array of call frames form the call stack.
class CallFrame extends ProxyHolder {

  CallFrame(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "FRAME: $callFrameId: $functionName\n"
      "${indent}this: ${self?.toString(indent + '  ')}\n"
      "${indent}ret: ${returnValue?.toString(indent + '  ')}\n"
      "${indent}fl: $functionLocation\n"
      "${indent}l: $location\n"
      "${indent}s: ${scopeChain.map((s) => s.toString(indent + '  '))}";

  /// Call frame identifier. This identifier is only valid while the virtual
  /// machine is paused.
  String get callFrameId => obj['callFrameId'];

  /// Name of the JavaScript function called on this call frame.
  String get functionName => obj['functionName'];

  /// Location in the source code. EXPERIMENTAL
  Location get functionLocation => obj['functionLocation'] == null
      ? null : new Location(obj['functionLocation']);

  /// Location in the source code.
  Location get location => obj['location'] == null
      ? null : new Location(obj['location']);

  /// Scope chain for this call frame.
  List<Scope> get scopeChain =>
      obj['scopeChain']?.map((obj) => new Scope(obj))?.toList() ?? [];

  /// this object for this call frame.
  RemoteObject get self => obj['this'] == null
      ? null : new RemoteObject(obj['this'], RemoteObjectType.self);

  /// The value being returned, if the function is at return point.
  RemoteObject get returnValue => obj['returnValue'] == null
      ? null : new RemoteObject(obj['returnValue'], RemoteObjectType.returnValue);
}

/// Call frames for assertions or error messages.
class StackTrace extends ProxyHolder {

  StackTrace(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "STACK: $description\n"
      "${indent}fr: ${callFrames.map((f) => f.toString(indent + '  '))}\n"
      "${indent}parent: $parent";

  /// String label of this stack trace. For async traces this may be a name of
  /// the function that initiated the async call.
  String get description => obj['description'];

  /// JavaScript function name.
  List<CallFrame> get callFrames =>
      obj['callFrames']?.map((obj) => new CallFrame(obj))?.toList() ?? [];

  /// Asynchronous JavaScript stack trace that preceded this stack, if
  /// available.
  StackTrace get parent => obj['description'] == null
      ? null : new StackTrace(obj['description']);
}

/// Detailed information about exception (or error) that was thrown during
/// script compilation or execution.
class ExceptionDetails extends ProxyHolder {

  ExceptionDetails(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "EXCEPTION: $exceptionId: $text\n"
      "${indent}exp: ${exception?.toString(indent + '  ')}\n"
      "${indent}stack: $stackTrace\n"
      "${indent}ctx: $scriptId, $executionContextId\n"
      "${indent}at: $lineNumber,$columnNumber\n"
      "${indent}u: $url";

  /// Exception id.
  int get exceptionId => obj['exceptionId'];

  /// Exception text, which should be used together with exception object when
  /// available.
  String get text => obj['text'];

  /// Line number of the exception location (0-based).
  int get lineNumber => obj['lineNumber'];

  /// Column number of the exception location (0-based).
  int get columnNumber => obj['columnNumber'];

  /// Script ID of the exception location.
  String get scriptId => obj['scriptId'];

  /// URL of the exception location, to be used when the script was not reported.
  String get url => obj['url'];

  /// JavaScript stack trace if available.
  StackTrace get stackTrace => obj['stackTrace'] == null
      ? null : new StackTrace(obj['stackTrace']);

  /// Exception object if available.
  RemoteObject get exception => obj['exception'] == null
      ? null : new RemoteObject(obj['exception'], RemoteObjectType.exception);

  /// Identifier of the context where exception happened.
  int get executionContextId => obj['executionContextId'];
}

enum RemoteObjectType {
  self,
  exception,
  scope,
  setter,
  getter,
  value,
  returnValue,
  result,
  symbol
}

/// Mirror object referencing original JavaScript object.
class RemoteObject extends ProxyHolder {

  final RemoteObjectType meta;

  RemoteObject(JsObject obj, this.meta) : super(obj);

  String toString([String indent = '  ']) =>
      "RO: $objectId: $className $type.$subtype $value\n"
      "${indent}u: $unserializableValue\n"
      "${indent}d: $description";

  /// Object type. Allowed values: object, function, undefined, string, number,
  /// boolean, symbol.
  String get type => obj['type'];

  /// Object subtype hint. Specified for object type values only.
  /// Allowed values: array, null, node, regexp, date, map, set, iterator,
  /// generator, error, proxy, promise, typedarray.
  String get subtype => obj['subtype'];

  /// Object class (constructor) name. Specified for object type values only.
  String get className => obj['className'];

  /// Remote object value in case of primitive values or JSON values (if it was
  /// requested).
  dynamic get value => obj['value'];

  /// Primitive value which can not be JSON-stringified does not have value, but
  /// gets this property.
  /// Infinity, NaN, -Infinity, -0.
  String get unserializableValue => obj['unserializableValue'];

  /// String representation of the object.
  String get description => obj['description'];

  /// Unique object identifier (for non-primitive values).
  String get objectId => obj['objectId'];

  /// TODO: Preview containing abbreviated property values. Specified for object
  /// type values only. EXPERIMENTAL
  /// ObjectPreview get preview

  /// TODO: EXPERIMENTAL
  /// CustomPreview customPreview
}

/// Represents function call argument. Either remote object id objectId,
/// primitive value, unserializable primitive value or neither of (for
/// undefined) them should be specified.
class CallArgument extends ProxyHolder {

  CallArgument(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "CALL: $objectId: $value\n"
      "${indent}u: $unserializableValue";

  /// Primitive value.
  dynamic get value => obj['value'];

  /// Primitive value which can not be JSON-stringified.
  /// Infinity, NaN, -Infinity, -0.
  String get unserializableValue => obj['unserializableValue'];

  /// Remote object handle.
  String get objectId => obj['objectId'];
}

/// Scope description.
class Scope extends ProxyHolder {

  Scope(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "SCOPE: $type:$name\n"
      "${indent}o: ${object?.toString(indent + '  ')}\n"
      "${indent}st: $startLocation\n"
      "${indent}en: $endLocation";

  /// Scope type. Allowed values: global, local, with, closure, catch, block,
  /// script.
  String get type => obj['type'];

  /// Object representing the scope. For global and with scopes it represents
  /// the actual object; for the rest of the scopes, it is artificial transient
  /// object enumerating scope variables as its properties.
  RemoteObject get object => obj['object'] == null
      ? null : new RemoteObject(obj['object'], RemoteObjectType.scope);

  String get name => obj['name'];

  /// Location in the source code where scope starts
  Location get startLocation => obj['startLocation'] == null
      ? null : new Location(obj['startLocation']);

  /// Location in the source code where scope ends
  Location get endLocation => obj['endLocation'] == null
      ? null : new Location(obj['endLocation']);
}

class ScriptParsed extends ProxyHolder {

  ScriptParsed(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "SCRIPT: $scriptId ($startLine:$startColumn,$endLine:$endColumn)\n"
      "${indent}u: $url\n"
      "${indent}m: $sourceMapURL\n"
      "${indent}id: $executionContextId, h: $hash";

  /// Identifier of the script parsed.
  String get scriptId => obj['scriptId'];

  /// URL or name of the script parsed (if any).
  String get url => obj['url'];

  /// Line offset of the script within the resource with given URL (for script
  /// tags).
  int get startLine => obj['startLine'];

  /// Column offset of the script within the resource with given URL.
  int get startColumn => obj['startColumn'];

  /// Last line of the script.
  int get endLine => obj['endLine'];

  /// Length of the last line of the script.
  int get endColumn => obj['endColumn'];

  /// Specifies script creation context.
  int get executionContextId => obj['executionContextId'];

  /// Content hash of the script.
  String get hash => obj['hash'];

  /// Embedder-specific auxiliary data.
  /// object get executionContextAuxData

  /// True, if this script is generated as a result of the live edit operation.
  /// EXPERIMENTAL
  /// bool get isLiveEdit

  /// URL of source map associated with script (if any).
  String get sourceMapURL => obj['sourceMapURL'];

  /// True, if this script has sourceURL. EXPERIMENTAL
  /// bool get hasSourceURL
}

class Location extends ProxyHolder {

  Location(JsObject obj) : super(obj);

  String toString() => "LOC: $scriptId ($lineNumber,$columnNumber)";

  /// Script identifier as reported in the Debugger.scriptParsed.
  String get scriptId => obj['scriptId'];

  /// Line number in the script (0-based).
  int get lineNumber => obj['lineNumber'];

  /// Column number in the script (0-based).
  int get columnNumber => obj['columnNumber'];

  Map toMap() => {
    'scriptId': scriptId,
    'lineNumber': lineNumber,
    'columnNumber': columnNumber
  };
}

class Property extends ProxyHolder {

  Property(JsObject obj) : super(obj);

  String toString([String indent = '  ']) =>
      "PROP: ${result.map((p) => p.toString(indent + '  '))}\n"
      "${indent}int: ${internalProperties.map((p) => p.toString(indent + '  '))}\n"
      "${indent}exp: ${exceptionDetails?.toString(indent + '  ')}";

  /// Object properties.
  List<PropertyDescriptor> get result =>
      obj['result']?.map((obj) => new PropertyDescriptor(obj))?.toList() ?? [];

  /// Internal object properties (only of the element itself).
  List<InternalPropertyDescriptor> get internalProperties =>
      obj['internalProperties']?.map((obj) => new InternalPropertyDescriptor(obj))?.toList() ?? [];

  /// Exception details.
  ExceptionDetails get exceptionDetails => obj['exceptionDetails'] == null
      ? null : new ExceptionDetails(obj['exceptionDetails']);
}

/// Object internal property descriptor. This property isn't normally visible
/// in JavaScript code.
class InternalPropertyDescriptor extends PropertyDescriptor {

  InternalPropertyDescriptor(JsObject obj) : super(obj);

  bool get isInternal => true;

  String toString([String indent = '  ']) =>
      "IPD: $name ${value?.toString(indent + '  ')}";
}

/// Object property descriptor.
class PropertyDescriptor extends ProxyHolder {

  PropertyDescriptor(JsObject obj) : super(obj);

  bool get isInternal => false;

  /// Conventional property name or symbol description.
  String get name => obj['name'];

  /// The value associated with the property.
  RemoteObject get value => obj['value'] == null
      ? null : new RemoteObject(obj['value'], RemoteObjectType.value);

  String toString([String indent = '  ']) =>
      "PD: $name ${value?.toString(indent + '  ')}\n"
      "${indent}fg: w: $writable c:$configurable e:$enumerable t:$wasThrown o:$isOwn\n"
      "${indent}get: ${getFunction.toString(indent + '  ')}\n"
      "${indent}set: ${setFunction.toString(indent + '  ')}\n"
      "${indent}sym: ${symbol?.toString(indent + '  ')}";

  /// True if the value associated with the property may be changed
  /// (data descriptors only).
  bool get writable => obj['writable'] == true;

  /// A function which serves as a getter for the property, or undefined if
  /// there is no getter (accessor descriptors only).
  RemoteObject get getFunction => obj['get'] == null
      ? null : new RemoteObject(obj['get'], RemoteObjectType.getter);

  /// A function which serves as a setter for the property, or undefined if
  /// there is no setter (accessor descriptors only).
  RemoteObject get setFunction => obj['set'] == null
      ? null : new RemoteObject(obj['set'], RemoteObjectType.setter);

  /// True if the type of this property descriptor may be changed and if the
  /// property may be deleted from the corresponding object.
  bool get configurable => obj['configurable'] == true;

  /// True if this property shows up during enumeration of the properties on
  /// the corresponding object.
  bool get enumerable => obj['enumerable'] == true;

  /// True if the result was thrown during the evaluation.
  bool get wasThrown => obj['wasThrown'] == true;

  /// True if the property is owned for the object.
  bool get isOwn => obj['isOwn'] == true;

  /// Property symbol object, if the property is of the symbol type.
  RemoteObject get symbol => obj['symbol'] == null
      ? null : new RemoteObject(obj['symbol'], RemoteObjectType.symbol);
}

class Breakpoint {
  /// Id of the created breakpoint for further reference.
  String breakpointId;

  /// Location this breakpoint resolved into.
  List<Location> locations;

  Breakpoint.setBreakpoint(JsObject obj)
      : breakpointId = obj['breakpointId'],
        locations = [new Location(obj['actualLocation'])];

  Breakpoint.setBreakpointByUrl(JsObject obj)
      : breakpointId = obj['breakpointId'],
        locations = obj['locations'].map((l) => new Location(l)).toList();

  Breakpoint.breakpointResolved(JsObject obj)
      : breakpointId = obj['breakpointId'],
        locations = [new Location(obj['location'])];

  String toString([String indent = '  ']) =>
      "BKPT: $breakpointId\n"
      "${indent}${locations.join('\n  ')}";
}
