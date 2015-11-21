// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library used for rebuilding the `dartlang` project.
library atom.rebuild;

import 'dart:async';

import '../atom.dart';
import '../jobs.dart';
import '../state.dart';
import '../utils.dart';
import 'pub.dart';

class RebuildManager implements Disposable {
  Disposables disposables = new Disposables();

  RebuildManager() {
    disposables.add(atom.commands.add('atom-workspace', 'dartlang:rebuild-restart-dev', (_) {
      new RebuildJob("Rebuilding dartlang").schedule();
    }));
    disposables.add(atom.commands.add('atom-workspace', 'dartlang:rebuild-run-tests-dev', (_) {
      new RebuildJob("Building dartlang tests", runTests: true).schedule();
    }));
  }

  void dispose() => disposables.dispose();
}

class RebuildJob extends Job {
  final bool runTests;

  RebuildJob(String title, {this.runTests: false}) : super(title, RebuildJob);

  Future run() {
    // Validate that there's an sdk.
    if (!sdkManager.hasSdk) {
      sdkManager.showNoSdkMessage();
      return new Future.value();
    }

    // Find the `dartlang` project.
    Directory proj = atom.project.getDirectories().firstWhere(
        (d) => d.getBaseName().endsWith(pluginId), orElse: () => null
    );
    if (proj == null) {
      atom.notifications.addWarning("Unable to find project '${pluginId}'.");
      return new Future.value();
    }

    // Save any dirty editors.
    atom.workspace.getTextEditors().forEach((editor) {
      if (editor.isModified()) editor.save();
    });

    List<String> args = ['grinder', runTests ? 'build-atom-tests' : 'build'];

    return new PubRunJob.local(proj.getPath(), args, title: name).schedule().then(
        (JobStatus status) {
      // Check for an exit code of `0` from grind build.
      if (status.isOk && status.result == 0) {
        if (runTests) {
          _runTests();
        } else {
          new Future.delayed(new Duration(seconds: 2)).then((_) => atom.reload());
        }
      }
    });
  }

  void _runTests() {
    TextEditor editor = atom.workspace.getActiveTextEditor();
    if (editor == null) {
      atom.notifications.addWarning("No active editor - can't run tests.");
    } else {
      atom.commands.dispatch(atom.views.getView(editor), 'window:run-package-specs');
    }
  }
}
