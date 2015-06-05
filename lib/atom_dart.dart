// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.dart;

import 'package:logging/logging.dart';

import 'atom/atom.dart';
import 'sdk.dart';
import 'utils.dart';

export 'package:atom_dart/atom/atom.dart' show registerPackage;

Logger _logger = new Logger("atom-dart");

class AtomDartPackage extends AtomPackage {
  final Disposables disposables = new Disposables();
  final Streams subscriptions = new Streams();

  SdkManager sdkManager;

  void packageActivated([Map state]) {
    _logger.fine("packageActivated");

    subscriptions.add(atom.project.onDidChangePaths.listen((e) {
      print("dirs = ${e}");
    }));

    sdkManager = new SdkManager();
    sdkManager.onSdkChange.listen((Sdk sdk) {
      print("sdk changed to ${sdk}");
      sdk.getVersion().then((ver) => print("version is ${ver}"));
    });
    disposables.add(sdkManager);

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
  }

  void packageDeactivated() {
    _logger.fine('packageDeactivated');
    disposables.dispose();
    subscriptions.cancel();
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
