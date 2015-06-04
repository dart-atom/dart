// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'atom.dart';

main() {
  registerPackage(new AtomDartPackage());
}

class AtomDartPackage extends AtomPackage {
  void packageActivated([Map state]) {
    //atom.beep();

    atom.commands.add('atom-workspace', 'dart-lang:hello-world', (e) {
      atom.notifications.addInfo(
        'Hello world from dart-lang!', options: {'detail': 'Foo bar.'});
    });
  }

  void packageDeactivated() {

  }
}
