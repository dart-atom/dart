// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.plugin;

import 'package:logging/logging.dart';

import 'atom.dart';
import 'dependencies.dart';
import 'sdk.dart';
import 'utils.dart';
import 'impl/rebuild.dart';
import 'impl/smoketest.dart';

export 'atom.dart' show registerPackage;

Logger _logger = new Logger("atom-dart");

class AtomDartPackage extends AtomPackage {
  final Disposables disposables = new Disposables();
  final StreamSubscriptions subscriptions = new StreamSubscriptions();

  AtomDartPackage();

  void packageActivated([Map state]) {
    _logger.fine("packageActivated");

    if (deps == null) Dependencies.setGlobalInstance(new Dependencies());

    SdkManager sdkManager = new SdkManager();
    sdkManager.onSdkChange.listen((Sdk sdk) {
      print("sdk changed to ${sdk}");
      if (sdk != null) {
        sdk.getVersion().then((ver) => print("version is ${ver}"));
      }
    });
    disposables.add(sdkManager);
    deps[SdkManager] = sdkManager;

    // Register commands.
    atom.commands.add('atom-workspace', 'dart-lang:smoke-test', (e) {
      smokeTest();
    });

    atom.commands.add('atom-workspace', 'dart-lang:rebuild-restart', (e) {
      new RebuildJob().schedule();
    });
  }

  void packageDeactivated() {
    _logger.fine('packageDeactivated');
    disposables.dispose();
    subscriptions.cancel();
  }

  Map config() {
    return {
      'sdkLocation': {
        'title': 'Dart SDK Location',
        'description': 'The location of the Dart SDK',
        'type': 'string',
        'default': ''
      }
    };
  }
}
