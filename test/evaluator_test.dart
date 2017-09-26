// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.evaluator_test;

import 'dart:async';

import 'package:test/test.dart';
import 'package:petitparser/petitparser.dart';

import '../lib/debug/evaluator.dart';

main() => defineTests();

defineTests() {
  group('Evaluator', () {
    Future testExpression(String input, [String expected]) async {
      EvaluatorReverseParser parser = new EvaluatorReverseParser();
      dynamic eval = parser.parse(parser.reverseString(input), 1000);
      EvalExpression expression = new EvalExpression('file.dart', eval);
      Evaluator evaluator = new Evaluator(expression);
      String result = await evaluator.eval();
      expect(result, expected ?? input);
    }

    Future failParse(String input) async {
      EvaluatorReverseParser parser = new EvaluatorReverseParser();
      expect(parser.reverseContextParser.parse(parser.reverseString(input)),
          new isInstanceOf<Failure>());
    }

    test('Testing a', () => testExpression('a'));
    test('Testing !a', () => testExpression('!a', 'a'));
    test('Testing a.b', () => testExpression('a.b'));
    test('Testing a.b.c', () => testExpression('a.b.c'));
    test('Testing a. b . c', () => testExpression('a. b . c', 'a.b.c'));
    test('Testing a . !b . c', () => testExpression('a . !b . c', 'b.c'));
    test('Testing a[c].b', () => testExpression('a[c].b'));
    test('Testing a[1].b', () => testExpression('a[1].b'));
    test('Testing a[1].b[1]', () => testExpression('a[1].b[1]'));
    test('Testing a[b[2]].c', () => testExpression('a[b[2]].c'));

    test('Failing on !', () => failParse('!'));
    // reverse parser we should never have a non id at the right
    test('Failing on a!', () => failParse('a!'));
  });
}
