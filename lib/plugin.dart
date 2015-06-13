// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.plugin;

import 'dart:async';

import 'package:logging/logging.dart';

import 'analysis_server.dart';
import 'atom.dart';
import 'atom_linter.dart';
import 'atom_statusbar.dart';
import 'dependencies.dart';
import 'projects.dart';
import 'sdk.dart';
import 'state.dart';
import 'utils.dart';
import 'impl/editing.dart' as editing;
import 'impl/pub.dart';
import 'impl/rebuild.dart';
import 'impl/smoketest.dart';
import 'impl/status_display.dart';

export 'atom.dart' show registerPackage;

final Logger _logger = new Logger("atom-dart");

class AtomDartPackage extends AtomPackage {
  final Disposables disposables = new Disposables();
  final StreamSubscriptions subscriptions = new StreamSubscriptions();
  final DartLinterProvider linterProvider = new DartLinterProvider();

  AtomDartPackage() {
    // Register a method to consume the `status-bar` service API.
    registerServiceConsumer('consumeStatusBar', (obj) {
      // Create a new status bar display.
      return new StatusDisplay(new StatusBar(obj));
    });

    // Register the linter provider.
    linterProvider.register();
  }

  void packageActivated([Map state]) {
    _logger.fine("packageActivated");

    if (deps == null) Dependencies.setGlobalInstance(new Dependencies());

    disposables.add(deps[SdkManager] = new SdkManager());
    disposables.add(deps[ProjectManager] = new ProjectManager());
    disposables.add(deps[AnalysisServer] = new AnalysisServer());

    // Register commands.
    _addCmd('atom-workspace', 'dart-lang:smoke-test', (_) => smokeTest());
    _addCmd('atom-workspace', 'dart-lang:rebuild-restart', (_) {
      new RebuildJob().schedule();
    });
    _addCmd('atom-workspace', 'dart-lang:auto-locate-sdk', (_) {
      new SdkLocationJob(sdkManager).schedule();
    });
    _addCmd('atom-workspace', 'dart-lang:refresh-dart-projects', (_) {
      new ProjectScanJob().schedule();
    });

    // Text editor commands.
    _addCmd('atom-text-editor', 'dart-lang:newline', editing.handleEnterKey);

    // Register commands that require an SDK to be present.
    _addSdkCmd('atom-text-editor', 'dart-lang:pub-get', (event) {
      // TODO: handle editors with no path
      // TODO: have a general find-me-the-dart-project utility
      new PubJob.get(dirname(event.editor.getPath())).schedule();
    });
    _addSdkCmd('atom-text-editor', 'dart-lang:pub-upgrade', (event) {
      new PubJob.upgrade(dirname(event.editor.getPath())).schedule();
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
        'description': 'The location of the Dart SDK.',
        'type': 'string',
        'default': ''
      }
    };
  }

  void _addCmd(String target, String command, void callback(AtomEvent e)) {
    disposables.add(atom.commands.add(target, command, callback));
  }

  // Validate that an sdk is available before calling the target function.
  void _addSdkCmd(String target, String command, void callback(AtomEvent e)) {
    disposables.add(atom.commands.add(target, command, (event) {
      if (!sdkManager.hasSdk) {
        sdkManager.showNoSdkMessage();
      } else {
        callback(event);
      }
    }));
  }
}

// TODO: move this class to a different file
class DartLinterProvider extends LinterProvider {
  // TODO: experiment with 'file', and lintOnFly: true
  DartLinterProvider() : super(scopes: ['source.dart'], scope: 'file', lintOnFly: false);

  void register() => LinterProvider.registerLinterProvider('provideLinter', this);

  Future<List<LintMessage>> lint(TextEditor editor, TextBuffer buffer) {
    // TODO: Lints are not currently displaying.

    return new Future.value([
      // new LintMessage(
      //   type: LintMessage.ERROR,
      //   message: 'foo bar',
      //   html: 'Foo bar baz',
      //   file: editor.getPath(),
      //   position: new Rn(new Pt(21, 1), new Pt(21, 10)))
    ]);
  }
}
