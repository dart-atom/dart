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

@Task('Analyze the source code with the ddc compiler')
ddc() {
  PubApp ddc = new PubApp.global('dev_compiler');
  ddc.run(['web/entry.dart'], script: 'devc');
}

@Task()
test() => new PubApp.local('test').run(['-rexpanded']);

// TODO: remove the `ddc` task for now - stream transformers make it unhappy.
@Task()
@Depends(analyze, build, test)
bot() => null;

@Task()
clean() {
  delete(getFile('web/entry.dart.js'));
  delete(getFile('web/entry.dart.js.deps'));
  delete(getFile('web/entry.dart.js.map'));
}

@Task('generate the analysis server API')
analysisServerApi() {
  // https://github.com/dart-lang/sdk/blob/master/pkg/analysis_server/tool/spec/spec_input.html
  Dart.run('tool/generate_analysis_lib.dart');
  DartFmt.format('lib/impl/analysis_server_gen.dart');
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
