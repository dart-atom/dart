// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.grind;

import 'dart:io';

import 'package:grinder/grinder.dart';

main(List args) => grind(args);

@Task()
test() {
  // TODO:

  log('test');
}

@Task()
build() {
  File inputFile = getFile('lib/atom_dart.dart');
  File outputFile = getFile('lib/atom_dart.dart.js');

  Dart2js.compile(inputFile, csp: true);
  outputFile.writeAsStringSync(_patchJSFile(outputFile.readAsStringSync()));
}

@Task()
clean() {
  delete(getFile('lib/atom_dart.dart.js'));
  delete(getFile('lib/atom_dart.dart.js.deps'));
  delete(getFile('lib/atom_dart.dart.js.map'));
}

final String _jsPrefix = """
var self = Object.create(this);
self.require = require;
self.module = module;
self.window = window;
self.atom = atom;
self.exports = exports;
self.Object = Object;

""";

String _patchJSFile(String input) {
  return _jsPrefix +
      input.replaceAll(r'if (typeof document === "undefined") {', "if (true) {");
}
