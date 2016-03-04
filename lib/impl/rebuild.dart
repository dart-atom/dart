// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library used for rebuilding the `dartlang` project.
library atom.rebuild;

import 'dart:async';

import 'package:atom/node/fs.dart';
import 'package:atom/utils/disposable.dart';

import '../atom.dart';
import '../jobs.dart';
import '../state.dart';
import 'pub.dart';

class RebuildManager implements Disposable {
  Disposables disposables = new Disposables();

  RebuildManager() {
    disposables.add(atom.commands.add('atom-workspace', 'dartlang:rebuild-restart-dev', (_) {
      new RebuildJob("Rebuilding Atom plugins").schedule();
    }));
  }

  void dispose() => disposables.dispose();
}

class RebuildJob extends Job {
  RebuildJob(String title) : super(title, RebuildJob);

  Future run() {
    // Validate that there's an sdk.
    if (!sdkManager.hasSdk) {
      sdkManager.showNoSdkMessage();
      return new Future.value();
    }

    // Save any dirty editors.
    atom.workspace.getTextEditors().forEach((editor) {
      if (editor.isModified()) editor.save();
    });

    // Determine names of plugins to build
    List<String> projNames = atom.config.getValue('$pluginId.buildAtomPlugins');
    if (projNames == null) projNames = [pluginId];

    // Build plugins and aggregate the results
    var builds = projNames.map((String name) => _runBuild(name));
    Future<bool> result = Future.wait(builds).then((List<bool> results) =>
        results.reduce((bool value, bool success) => value && success));

    return result.then((bool success) {
      if (success) {
        new Future.delayed(new Duration(seconds: 2)).then((_) => atom.reload());
      }
    });
  }

  /// Locate and build the specified project.
  Future<bool> _runBuild(String projName) {
    // Find the project to be built.
    Directory proj = atom.project.getDirectories().firstWhere(
      (d) => d.getBaseName().endsWith(projName), orElse: () => null
    );
    if (proj == null) {
      atom.notifications.addWarning("Unable to find project '${projName}'.");
      return new Future.value(false);
    }

    List<String> args = ['grinder', 'build'];

    // Run the build and check for an exit code of `0` from grind build.
    return new PubRunJob.local(proj.getPath(), args, title: projName)
      .schedule().then((JobStatus status) => status.isOk && status.result == 0);
  }
}
