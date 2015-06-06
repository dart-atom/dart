// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../jobs.dart';

class RebuildJob extends Job {
  RebuildJob() : super("Rebuilding 'dart-lang'");

  Future run() {
    return new Future.delayed(new Duration(seconds: 4));
  }
}
