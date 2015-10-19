
import 'package:atom_dartlang/flutter/launch_flutter.dart';
import 'package:test/test.dart';

// TODO: Test library based on classes?

defineTests() {
  group('launch_flutter', () {
    group('FlutterUriTranslator', groupFlutterUriTranslator);
  });
}

groupFlutterUriTranslator() {
  FlutterUriTranslator x = new FlutterUriTranslator('/projects/foo_bar');

  test('targetToClient package:', () {
    expect(
      x.targetToClient('http://localhost:9888/packages/flutter/src/material/dialog.dart'),
      'package:flutter/src/material/dialog.dart');
  });

  test('targetToClient file:', () {
    expect(
      x.targetToClient('http://localhost:9888/lib/main.dart'),
      'file:///projects/foo_bar/lib/main.dart');
  });

  test('targetToClient dart:', () {
    expect(x.targetToClient('dart:core/core.dart'), 'dart:core/core.dart');
  });

  test('clientToTarget package:', () {
    expect(
      x.clientToTarget('package:flutter/src/material/dialog.dart'),
      'http://localhost:9888/packages/flutter/src/material/dialog.dart');
  });

  test('clientToTarget file:', () {
    expect(
      x.clientToTarget('file:///projects/foo_bar/lib/main.dart'),
      'http://localhost:9888/lib/main.dart');
  });

  test('clientToTarget dart:', () {
    expect(x.clientToTarget('dart:core/core.dart'), 'dart:core/core.dart');
  });
}
