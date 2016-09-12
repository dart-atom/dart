// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.grind;

import 'dart:io';

import 'package:grinder/grinder.dart';
import 'package:which/which.dart';

import 'package:atom/build/build.dart';
import 'package:atom/build/publish.dart';

main(List<String> args) => grind(args);

@Task()
analyze() => new PubApp.global('tuneup').runAsync(['check', '--ignore-infos']);

@DefaultTask()
build() async {
  File inputFile = getFile('web/entry.dart');
  File outputFile = getFile('web/entry.dart.js');

  // --trust-type-annotations? --trust-primitives?
  await Dart2js.compileAsync(inputFile, csp: true, extraArgs: ['--show-package-warnings']);
  outputFile.writeAsStringSync(patchDart2JSOutput(outputFile.readAsStringSync()));
}

@Task('Build the Atom tests')
buildAtomTests() async {
  final String base = 'spec/all-spec';
  File inputFile = getFile('${base}.dart');
  File outputFile = getFile('${base}.js');
  await Dart2js.compileAsync(inputFile, csp: true, outFile: outputFile);
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

@Task()
@Depends(build) //analyze, build, test, runAtomTests)
publish() => publishAtomPlugin();

@Task()
test() => Dart.runAsync('test/all.dart');

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
  DartFmt.format('lib/analysis/analysis_server_lib.dart', lineLength: 90);
}

@Task()
@Depends(analysisApi)
generate() => null;
