import 'dart:async';

import '../launch/launch.dart';
import '../utils.dart';

abstract class DebugConnection {
  final Launch launch;
  final Property<String> metadata = new Property();

  final SelectionGroup<DebugIsolate> isolates = new SelectionGroup();

  DebugConnection(this.launch);

  List<DebugOption> get options => [];

  bool get isAlive;

  Stream<DebugIsolate> get onPaused;
  Stream<DebugIsolate> get onResumed;

  Future terminate();

  Future get onTerminated;

  Future resume();
  stepIn();
  stepOver();
  stepOut();
  stepOverAsyncSuspension();
  autoStepOver();

  void dispose();
}

abstract class DebugOption {
  String get label;

  bool get checked;
  set checked(bool state);
}

// TODO: Add an IsolateState class.

/// A representation of a VM Isolate.
abstract class DebugIsolate extends MItem {
  DebugIsolate();

  String get id => name;

  String get name;

  /// Return a more human readable name for the Isolate.
  String get displayName => name;

  String get detail;

  bool get suspended;

  bool get hasFrames => frames != null && frames.isNotEmpty;

  List<DebugFrame> get frames;

  pause();
  Future resume();
  stepIn();
  stepOver();
  stepOut();
  stepOverAsyncSuspension();
  autoStepOver();
}

abstract class DebugFrame extends MItem {
  DebugFrame();

  String get id => title;

  String get title;

  bool get isSystem;
  bool get isExceptionFrame;

  List<DebugVariable> get locals;

  Future<List<DebugVariable>> resolveLocals() => new Future.value(locals);

  DebugLocation get location;

  Future<String> eval(String expression);

  String toString() => title;
}

abstract class DebugVariable extends MItem {
  String get id => name;

  String get name;
  DebugValue get value;

  String toString() => name;
}

abstract class DebugValue {
  String get className;

  String get valueAsString;

  bool get isPrimitive;
  bool get isString;
  bool get isPlainInstance;
  bool get isList;
  bool get isMap;

  bool get valueIsTruncated;

  int get itemsLength;

  String get hint {
    if (isString) {
      // We choose not to escape double quotes here; it doesn't work well visually.
      String str = valueAsString;
      return valueIsTruncated ? '"$str…' : '"$str"';
    } else if (isList) {
      return '[ $itemsLength ]';
    } else if (isMap) {
      return '{ $itemsLength }';
    } else if (itemsLength != null) {
      return '$className [ $itemsLength ]';
    } else if (isPlainInstance) {
      return className;
    } else {
      return valueAsString;
    }
  }

  Future<List<DebugVariable>> getChildren();

  Future<DebugValue> invokeToString();

  String toString() => valueAsString;
}

abstract class DebugLocation {
  /// A file path.
  String get path;

  /// 1-based line number.
  int get line;

  /// 1-based column number.
  int get column;

  /// A display file path.
  String get displayPath;

  bool resolved = false;

  DebugLocation();

  Future<DebugLocation> resolve();

  String toString() => '${path} ${line}:${column}';
}
