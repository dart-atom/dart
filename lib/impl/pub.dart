// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.pub;

import 'dart:async';

import '../atom.dart';
import '../jobs.dart';
import '../sdk.dart';
import '../state.dart';
import '../utils.dart';

const String pubspecFileName = 'pubspec.yaml';

class PubJob extends Job {
  final String path;
  final String pubCommand;

  String _pubspecDir;

  PubJob.get(this.path) : pubCommand = 'get', super('Pub get') {
    _locatePubspecDir();
  }

  PubJob.upgrade(this.path) : pubCommand = 'upgrade', super('Pub upgrade') {
    _locatePubspecDir();
  }

  bool get pinResult => true;

  Object get schedulingRule => _pubspecDir;

  Future run() {
    return sdkManager.sdk.execBinSimple('pub', [pubCommand], cwd: _pubspecDir).then(
        (ProcessResult result) {
      if (result.exit != 0) throw '${result.stdout}\n${result.stderr}';
      return result.stdout;
    });
  }

  void _locatePubspecDir() {
    Directory dir = new Directory.fromPath(path);

    if (new File.fromPath(join(path, pubspecFileName)).existsSync()) {
      _pubspecDir = dir.path;
      return;
    }

    while (!dir.isRoot() && dir.path.length > 2) {
      if (dir.getFile(pubspecFileName).existsSync()) {
        _pubspecDir = dir.path;
        break;
      }
      dir = dir.getParent();
    }
  }
}
