import 'package:atom_dartlang/flutter/flutter_launch.dart';

import '../_spec/test.dart';

void register() {
  registerSuite(new FlutterUriTranslatorTest());
}

class FlutterUriTranslatorTest extends TestSuite {
  FlutterUriTranslator x = new FlutterUriTranslator('/projects/foo_bar');

  Map<String, Test> getTests() => {
    'targetToClient_package': _targetToClient_package,
    'targetToClient_file': _targetToClient_file,
    'targetToClient_dart': _targetToClient_dart,
    'clientToTarget_package': _clientToTarget_package,
    'clientToTarget_file': _clientToTarget_file,
    'clientToTarget_dart': _clientToTarget_dart
  };

  _targetToClient_package() {
    expect(
      x.targetToClient('package:flutter/src/material/dialog.dart'),
      'package:flutter/src/material/dialog.dart'
    );
  }

  _targetToClient_file() {
    expect(
      x.targetToClient('/projects/foo_bar/lib/main.dart'),
      '/projects/foo_bar/lib/main.dart'
    );
  }

  _targetToClient_dart() {
    expect(x.targetToClient('dart:core/core.dart'), 'dart:core/core.dart');
  }

  _clientToTarget_package() {
    expect(
      x.clientToTarget('package:flutter/src/material/dialog.dart'),
      'package:flutter/src/material/dialog.dart'
    );
  }

  _clientToTarget_file() {
    expect(
      x.clientToTarget('/projects/foo_bar/lib/main.dart'),
      '/projects/foo_bar/lib/main.dart'
    );
  }

  _clientToTarget_dart() {
    expect(x.clientToTarget('dart:core/core.dart'), 'dart:core/core.dart');
  }
}
