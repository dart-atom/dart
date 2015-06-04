// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:atom_dart/atom/atom.dart';
import 'package:logging/logging.dart';

Logger _logger = new Logger("AtomDartPackage");

main() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.message}');
  });

  registerPackage(new AtomDartPackage());
}

class AtomDartPackage extends AtomPackage {
  void packageActivated([Map state]) {

    atom.commands.add('atom-workspace', 'dart-lang:hello-world', (e) {
      atom.notifications.addInfo(
        'Hello world from dart-lang!', options: {'detail': 'Foo bar.'});

      BufferedProcess.create('ls',
        args: ['-l'],
        stdout: (str) => print("stdout: ${str}"),
        stderr: (str) => print("stderr: ${str}"),
        exit: (code) => print('exit code = ${code}'));

      _logger.fine("Hello notification from dart-lang");
    });

    atom.config.observe('dart-lang.sdkLocation', null, (value) {
      _logger.info('SDK location = ${value}');
    });

    //atom.beep();
  }

  void packageDeactivated() =>
    _logger.fine('AtomDartPackage.packageDeactivated');

  Map config() {
    return {
      'sdkLocation': {
        'title': 'Dart SDK Location',
        'description': 'The location of the Dart SDK',
        'type': 'string',
        'default': ''
      }
    };
  }
}
