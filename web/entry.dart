// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.entry;

import 'package:atom_dartlang/plugin.dart';
import 'package:logging/logging.dart';

main() {
  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen(print);

  registerPackage(new AtomDartPackage());
}
