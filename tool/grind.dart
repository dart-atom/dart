// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.grind;

import 'dart:convert';
import 'dart:io';

import 'package:grinder/grinder.dart';
import 'package:pub_semver/pub_semver.dart';

part "publish.dart";

// crashes grinder -- so add it as a library dependency for now.
// import 'deploy.dart' show deploy;
// export 'publish.dart' show deploy;

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

  // Patch in the GA UA code; replace "UA-000000-0" with a valid code.
  String code = Platform.environment['DARTLANG_UA'];
  if (code != null) {
    log('Patching with the dartlang Google Analytics code.');

    String str = outputFile.readAsStringSync();
    str = str.replaceAll('"UA-000000-0"', '"${code}"');
    outputFile.writeAsStringSync(str);
  } else {
    log('No \$DARTLANG_UA environment variable set.');
  }
}

@Task('Analyze the source code with the ddc compiler')
ddc() {
  PubApp ddc = new PubApp.global('dev_compiler');
  ddc.run(['web/entry.dart'], script: 'devc');
}

@Task()
test() => new PubApp.local('test').run(['-rexpanded']);

// TODO: remove the `ddc` dep task for now - stream transformers make it unhappy.
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
analysisApi() {
  // https://github.com/dart-lang/sdk/blob/master/pkg/analysis_server/tool/spec/spec_input.html
  Dart.run('tool/analysis/generate_analysis.dart', packageRoot: 'packages');
  DartFmt.format('lib/analysis/analysis_server_gen.dart');
}

@Task('generate the observatory API')
observatoryApi() {
  // https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md
  Dart.run('tool/observatory/generate_observatory.dart',
      packageRoot: 'packages');
  DartFmt.format('lib/impl/observatory_gen.dart');
}

@Task('generate both the observatory and analysis APIs')
@Depends(analysisApi, observatoryApi)
generate() => null;

final String _jsPrefix = """
var self = Object.create(this);
self.require = require;
self.module = module;
self.window = window;
self.atom = atom;
self.exports = exports;
self.Object = Object;
self.Promise = Promise;
self.setTimeout = function(f, millis) { return window.setTimeout(f, millis); };
self.clearTimeout = function(id) { window.clearTimeout(id); };
self.setInterval = function(f, millis) { return window.setInterval(f, millis); };
self.clearInterval = function(id) { window.clearInterval(id); };

// Work around interop issues.
self.getTextEditorForElement = function(element) { return element.o.getModel(); };

""";

String _patchJSFile(String input) {
  final String from_1 = 'if (document.currentScript) {';
  final String from_2 = "if (typeof document.currentScript != 'undefined') {";
  final String to = 'if (true) {';

  int index = input.lastIndexOf(from_1);
  if (index != -1) {
    input = input.substring(0, index) + to + input.substring(index + from_1.length);
  } else {
    index = input.lastIndexOf(from_2);
    input = input.substring(0, index) + to + input.substring(index + from_2.length);
  }
  return _jsPrefix + input;
}
