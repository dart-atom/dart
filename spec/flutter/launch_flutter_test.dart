@MirrorsUsed(targets: const [FlutterUriTranslatorTest])
import 'dart:mirrors';

import 'package:atom_dartlang/flutter/launch_flutter.dart';

import '../_spec/test.dart';

void register() {
  registerSuite(FlutterUriTranslatorTest);
}

class FlutterUriTranslatorTest extends TestSuite {
  FlutterUriTranslator x = new FlutterUriTranslator('/projects/foo_bar');

  @Test()
  targetToClient_package() {
    expect(
      x.targetToClient('packages/flutter/src/material/dialog.dart'),
      'package:flutter/src/material/dialog.dart');
  }

  @Test()
  targetToClient_file() {
    expect(
      x.targetToClient('/projects/foo_bar/lib/main.dart'),
      '/projects/foo_bar/lib/main.dart');
  }

  @Test()
  targetToClient_dart() {
    expect(x.targetToClient('dart:core/core.dart'), 'dart:core/core.dart');
  }

  @Test()
  clientToTarget_package() {
    expect(
      x.clientToTarget('package:flutter/src/material/dialog.dart'),
      'packages/flutter/src/material/dialog.dart');
  }

  @Test()
  clientToTarget_file() {
    expect(
      x.clientToTarget('/projects/foo_bar/lib/main.dart'),
      '/projects/foo_bar/lib/main.dart');
  }

  @Test()
  clientToTarget_dart() {
    expect(x.clientToTarget('dart:core/core.dart'), 'dart:core/core.dart');
  }
}
