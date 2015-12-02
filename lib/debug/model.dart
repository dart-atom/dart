import 'dart:async';

/// A representation of a VM Isolate.
abstract class DebugIsolate {
  DebugIsolate();

  String get name;
}

abstract class DebugFrame {
  DebugFrame();

  String get title;

  String get cursorDescription;

  List<DebugVariable> get locals;

  Future<DebugLocation> getLocation();

  Future<String> eval(String expression);

  String toString() => title;
}

abstract class DebugVariable {
  DebugVariable();

  String get name;
  String get valueDescription;

  String toString() => name;
}

class DebugLocation {
  /// A file path;
  final String path;
  /// 1-based line number.
  final int line;
  /// 1-based column number.
  final int column;

  DebugLocation(this.path, this.line, this.column);

  String toString() => '${path} ${line}:${column}';
}
