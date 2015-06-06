// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.editing;

import '../atom.dart';

/// Handle special behavior for the enter key in Dart files.
void handleEnterKey(AtomEvent event) {
  //print(event);
  event.abortKeyBinding();
}
