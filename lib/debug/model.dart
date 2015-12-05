import 'dart:async';

import '../launch/launch.dart';
import '../utils.dart';

abstract class DebugConnection {
  final Launch launch;
  final Property<String> metadata = new Property();

  final SelectionGroup<DebugIsolate> isolates = new SelectionGroup();

  DebugConnection(this.launch);

  bool get isAlive;

  // TODO: remove
  DebugIsolate get isolate;

  Stream<DebugIsolate> get onPaused;
  Stream<DebugIsolate> get onResumed;

  Future terminate();

  Future get onTerminated;

  Future resume();
  stepIn();
  stepOver();
  stepOut();

  void dispose();
}

/// A representation of a VM Isolate.
abstract class DebugIsolate {
  final Property<bool> suspended = new Property(false);

  DebugIsolate();

  String get name;

  String get detail;

  bool get isSuspended => suspended.value;

  // TODO: state

  bool get hasFrames => frames != null && frames.isNotEmpty;

  List<DebugFrame> get frames;

  pause();
  Future resume();
  stepIn();
  stepOver();
  stepOut();
}

abstract class DebugFrame {
  DebugFrame();

  String get title;

  List<DebugVariable> get locals;

  DebugLocation get location;

  Future<String> eval(String expression);

  String toString() => title;
}

abstract class DebugVariable {
  DebugVariable();

  String get name;
  String get valueDescription;

  String toString() => name;
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

  bool get resolvedPath => path != null;

  bool resolved = false;

  DebugLocation();

  Future<DebugLocation> resolve();

  String toString() => '${path} ${line}:${column}';
}
