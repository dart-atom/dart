// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.grind;

import 'dart:io';

import 'package:grinder/grinder.dart';

main(List args) => grind(args);

@Task()
analyze() {
  new PubApp.global('tuneup').run(['check']);
}

@DefaultTask()
build() {
  File inputFile = getFile('web/entry.dart');
  File outputFile = getFile('web/entry.dart.js');

  // --trust-type-annotations? --trust-primitives?
  Dart2js.compile(inputFile, csp: true);
  outputFile.writeAsStringSync(_patchJSFile(outputFile.readAsStringSync()));
}

@Task()
test() => new PubApp.local('test').run(['-rexpanded']);

@Task()
@Depends(analyze, build, test)
bot() => null;

@Task()
clean() {
  delete(getFile('web/entry.dart.js'));
  delete(getFile('web/entry.dart.js.deps'));
  delete(getFile('web/entry.dart.js.map'));
}

final String _jsPrefix = """
var self = Object.create(this);
self.require = require;
self.module = module;
self.window = window;
self.atom = atom;
self.exports = exports;
self.Object = Object;
self.Promise = Promise;
self.setTimeout = function(f, millis) { window.setTimeout(f, millis); };

""";

String _patchJSFile(String input) {
  final String from = 'if (document.currentScript) {';
  final String to = 'if (true) { // document.currentScript';

  int index = input.lastIndexOf(from);
  input = input.substring(0, index) + to + input.substring(index + from.length);
  return _jsPrefix + input;
}
