// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.dart;

import 'package:atom_dart/atom/atom.dart';
import 'package:logging/logging.dart';

export 'package:atom_dart/atom/atom.dart' show registerPackage;

Logger _logger = new Logger("atom-dart");

class AtomDartPackage extends AtomPackage {
  Disposables disposables = new Disposables();

  void packageActivated([Map state]) {
    _logger.fine("packageActivated");

    disposables.add(atom.project.onDidChangePaths((e) {
      print("dirs = ${e}");
    }));

    atom.commands.add('atom-workspace', 'dart-lang:hello-world', (e) {
      atom.notifications.addInfo(
        'Hello world from dart-lang!', options: {'detail': 'Foo bar.'});

      // BufferedProcess.create('ls',
      //   args: ['-l'],
      //   stdout: (str) => print("stdout: ${str}"),
      //   stderr: (str) => print("stderr: ${str}"),
      //   exit: (code) => print('exit code = ${code}'));

      print("directories = ${atom.project.getDirectories()}");
    });

    atom.config.observe('dart-lang.sdkLocation', null, (value) {
      _logger.info('SDK location = ${value}');
    });
  }

  void packageDeactivated() {
    _logger.fine('packageDeactivated');
    disposables.dispose();
  }

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
