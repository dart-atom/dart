// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library used for rebuilding the `dartlang` project.
library atom.rebuild;

import 'dart:async';

import 'pub.dart';
import '../atom.dart';
import '../jobs.dart';
import '../state.dart';

class RebuildJob extends Job {
  RebuildJob() : super("Rebuilding dart-lang", RebuildJob);

  Future run() {
    // Validate that there's an sdk.
    if (!sdkManager.hasSdk) {
      sdkManager.showNoSdkMessage();
      return new Future.value();
    }

    // Find the `dartlang` project.
    Directory proj = atom.project.getDirectories().firstWhere(
        (d) => d.getBaseName().endsWith(pluginId), orElse: () => null);
    if (proj == null) {
      atom.notifications.addWarning("Unable to find project '${pluginId}'.");
      return new Future.value();
    }

    // Save any dirty editors.
    atom.workspace.getTextEditors().forEach((editor) {
      if (editor.isModified()) editor.save();
    });

    return new PubRunJob.local(proj.getPath(), ['grinder', 'build']).schedule().then(
        (JobStatus status) {
      // Check for an exit code of `0` from grind build.
      if (status.isOk && status.result == 0) {
        new Future.delayed(new Duration(seconds: 2)).then((_) => atom.reload());
      }
    });
  }
}
