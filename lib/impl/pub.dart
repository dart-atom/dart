// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.pub;

import 'dart:async';

import '../jobs.dart';
import '../sdk.dart';
import '../state.dart';

class PubJob extends Job {
  final String path;
  final String pubCommand;

  PubJob.get(this.path) : pubCommand = 'get', super('Pub get');

  PubJob.upgrade(this.path) : pubCommand = 'upgrade', super('Pub upgrade');

  bool get pinResult => true;

  Future run() {
    return sdkManager.sdk.execBinSimple('pub', [pubCommand], cwd: path).then(
        (ProcessResult result) {
      if (result.exit != 0) throw '${result.stdout}\n${result.stderr}';
      return result.stdout;
    });
  }
}
