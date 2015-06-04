// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:atom_dart/atom.dart';
import 'package:logging/logging.dart';

Logger _logger = new Logger("AtomDartPackage");

main() {

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.message}');
  });

  registerPackage(new AtomDartPackage());

}

class AtomDartPackage extends AtomPackage {
  void packageActivated([Map state]) {
    _logger.fine('AtomDartPackage.packageActivated, state: $state');

    //atom.beep();

    atom.commands.add('atom-workspace', 'dart-lang:hello-world', (e) {
      atom.notifications.addInfo(
        'Hello world from dart-lang!', options: {'detail': 'Foo bar.'});
      _logger.info("Hello notification from dart-lang");
    });
  }

  void packageDeactivated() {
    _logger.fine('AtomDartPackage.packageDeactivated');


  }
}
