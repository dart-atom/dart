// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library used for rebuilding the `dartlang` project.
library atom.rebuild;

import 'dart:async';

import '../atom.dart';
import '../jobs.dart';
import '../sdk.dart';
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
    final String projName = 'dartlang';
    Directory proj = atom.project.getDirectories().firstWhere(
        (d) => d.getBaseName().endsWith(projName), orElse: () => null);
    if (proj == null) {
      atom.notifications.addWarning("Unable to find project '${projName}'.");
      return new Future.value();
    }

    // Save any dirty editors.
    atom.workspace.getTextEditors().forEach((editor) {
      if (editor.isModified()) editor.save();
    });

    // Run dart2js --csp -oweb/entry.dart.js web/entry.dart.
    Sdk sdk = sdkManager.sdk;

    Future f = sdk.execBinSimple(
        'dart2js',
        ['--csp', '-oweb/entry.dart.js', '--show-package-warnings', 'web/entry.dart'],
        cwd: proj);

    return f.then((ProcessResult result) {
      if (result.exit == 0) {
        File file = proj.getSubdirectory('web').getFile('entry.dart.js');
        file.read().then((contents) {
          file.writeSync(_patchJSFile(contents));
        });
      }

      if (result.stdout.isNotEmpty) {
        throw '${result.stdout}\n${result.stderr}';
      } else {
        atom.notifications.addSuccess("Recompiled dart-tools! Restarting…");

        return new Future.delayed(new Duration(seconds: 1)).then((_) {
          // re-start atom
          atom.reload();
        });
      }
    });
  }
}

// From tool/grind.dart.
final String _jsPrefix = """
var self = Object.create(this);
self.require = require;
self.module = module;
self.window = window;
self.atom = atom;
self.exports = exports;
self.Object = Object;
self.Promise = Promise;
self.setTimeout = function(f, millis) { return window.setTimeout(f, millis); };
self.clearTimeout = function(id) { window.clearTimeout(id); };
self.setInterval = function(f, millis) { return window.setInterval(f, millis); };
self.clearInterval = function(id) { window.clearInterval(id); };

""";

String _patchJSFile(String input) {
  final String from = 'if (document.currentScript) {';
  final String to = 'if (true) { // document.currentScript';

  int index = input.lastIndexOf(from);
  input = input.substring(0, index) + to + input.substring(index + from.length);
  return _jsPrefix + input;
}
