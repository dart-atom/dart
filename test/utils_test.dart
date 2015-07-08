// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.utils_test;

import 'package:atom_dartlang/utils.dart';
import 'package:test/test.dart';

main() => defineTests();

defineTests() {
  group('utils', () {
    test('toStartingLowerCase', () {
      expect(toStartingLowerCase(''), '');
      expect(toStartingLowerCase('a'), 'a');
      expect(toStartingLowerCase('A'), 'a');
      expect(toStartingLowerCase('ABC'), 'aBC');
      expect(toStartingLowerCase('abc'), 'abc');
    });

    test('simpleDiff', () {
      _checkDiff(simpleDiff('aabcc', 'aacc'), new Edit(0, 5, 'aacc'));
    });
  });
}

_checkDiff(List<Edit> edits, Edit expectEdit) {
  expect(edits.length, 1);
  expect(edits.first, expectEdit);
}
