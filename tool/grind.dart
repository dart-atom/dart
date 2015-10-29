// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.grind;

import 'dart:convert';
import 'dart:io';

import 'package:grinder/grinder.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:which/which.dart';

part 'publish.dart';

main(List<String> args) => grind(args);

@Task()
analyze() => new PubApp.global('tuneup').runAsync(['check']);

@DefaultTask()
build() async {
  File inputFile = getFile('web/entry.dart');
  File outputFile = getFile('web/entry.dart.js');

  // --trust-type-annotations? --trust-primitives?
  await Dart2js.compileAsync(inputFile, csp: true);
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

@Task('Build the Atom tests')
buildAtomTests() async {
  final String base = 'spec/all-spec';
  File inputFile = getFile('${base}.dart');
  await Dart2js.compileAsync(inputFile,
      csp: true,
      enableExperimentalMirrors: true,
      outFile: getFile('${base}.js'));
  delete(getFile('${base}.js.deps'));
}

@Task('Run the Atom tests')
@Depends(buildAtomTests)
runAtomTests() async {
  String apmPath = whichSync('apm', orElse: () => null);

  if (apmPath != null) {
    await runAsync('apm', arguments: ['test']);
  } else {
    log("warning: command 'apm' not found");
  }
}

@Task('Analyze the source code with ddc')
ddc() {
  return new DevCompiler().analyzeAsync(
    getFile('web/entry.dart'), htmlOutput: true);
}

@Task()
test() => new PubApp.local('test').runAsync(['-rexpanded']);

// TODO: Removed the `ddc` dep task for now.
@Task()
@Depends(analyze, build, test, runAtomTests)
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
  DartFmt.format('lib/analysis/analysis_server_lib.dart');
}

@Task()
@Depends(analysisApi)
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

self._domHoist = function(element, targetQuery) {
  var target = document.querySelector(targetQuery);
  target.appendChild(element);
};

self._domRemove = function(element) {
  element.parentNode.removeChild(element);
};
""";

String _patchJSFile(String input) {
  final String from_1 = 'if (document.currentScript) {';
  final String from_2 = "if (typeof document.currentScript != 'undefined') {";
  final String to = 'if (true) {';

  int index = input.lastIndexOf(from_1);
  if (index != -1) {
    input =
        input.substring(0, index) + to + input.substring(index + from_1.length);
  } else {
    index = input.lastIndexOf(from_2);
    input =
        input.substring(0, index) + to + input.substring(index + from_2.length);
  }
  return _jsPrefix + input;
}
