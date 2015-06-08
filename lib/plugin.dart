// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.plugin;

import 'package:logging/logging.dart';

import 'atom.dart';
import 'atom_statusbar.dart';
import 'dependencies.dart';
import 'sdk.dart';
import 'state.dart';
import 'utils.dart';
import 'impl/editing.dart';
import 'impl/pub.dart';
import 'impl/rebuild.dart';
import 'impl/smoketest.dart';
import 'impl/status.dart';

export 'atom.dart' show registerPackage;

final Logger _logger = new Logger("atom-dart");

class AtomDartPackage extends AtomPackage {
  final Disposables disposables = new Disposables();
  final StreamSubscriptions subscriptions = new StreamSubscriptions();

  AtomDartPackage() {
    // Register a method to consume the `status-bar` service API.
    registerMethod('consumeStatusBar', (obj) {
      // Create a new status bar display.
      return new StatusDisplay(new StatusBar(obj));
    });
  }

  void packageActivated([Map state]) {
    _logger.fine("packageActivated");

    if (deps == null) Dependencies.setGlobalInstance(new Dependencies());

    SdkManager sdkManager = new SdkManager();
    deps[SdkManager] = sdkManager;
    disposables.add(sdkManager);

    // Register commands.
    CommandRegistry cmds = atom.commands;
    cmds.add('atom-workspace', 'dart-lang:smoke-test', (_) => smokeTest());
    cmds.add('atom-workspace', 'dart-lang:rebuild-restart', (_) {
      new RebuildJob().schedule();
    });
    cmds.add('atom-text-editor', 'dart-lang:newline', handleEnterKey);
    cmds.add('atom-text-editor', 'dart-lang:pub-get',
        _sdkCommand((AtomEvent event) {
      new PubJob.get(dirname(event.editor.getPath())).schedule();
    }));
    cmds.add('atom-text-editor', 'dart-lang:pub-upgrade',
        _sdkCommand((AtomEvent event) {
      new PubJob.upgrade(dirname(event.editor.getPath())).schedule();
    }));
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

  // Validate that an sdk is available before calling the target function.
  Function _sdkCommand(Function f) => (arg) {
    if (!sdkManager.hasSdk) {
      sdkManager.showNoSdkMessage();
    } else {
      f(arg);
    }
  };
}
