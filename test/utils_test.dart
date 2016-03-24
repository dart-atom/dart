// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.utils_test;

import 'dart:async';

import 'package:atom/utils/string_utils.dart';
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

    test('simpleDiff 1', () {
      _checkDiff(simpleDiff('aabcc', 'aacc'), new Edit(2, 1, ''));
    });

    test('simpleDiff 2', () {
      _checkDiff(simpleDiff('aaa', 'bbb'), new Edit(0, 3, 'bbb'));
    });

    test('simpleDiff 3', () {
      _checkDiff(simpleDiff('aabb', 'aabbc'), new Edit(4, 0, 'c'));
    });

    test('simpleDiff 4', () {
      _checkDiff(simpleDiff('abbb', 'bbb'), new Edit(0, 1, ''));
    });

    test('simpleDiff 5', () {
      _checkDiff(simpleDiff('aabb', 'aabb'), new Edit(0, 0, ''));
    });

    test('simpleDiff 6', () {
      _checkDiff(simpleDiff('', 'aabb'), new Edit(0, 0, 'aabb'));
    });

    test('simpleDiff 7', () {
      _checkDiff(simpleDiff('aabb', ''), new Edit(0, 4, ''));
    });
  });

  group('Property', () {
    test('mutate value', () {
      Property<int> p = new Property();
      expect(p.value, null);
      p.value = 123;
      expect(p.value, 123);
    });

    test('mutation fires event', () {
      Property<String> p = new Property();
      expect(p.value, null);
      Future f = p.onChanged.first;
      p.value = '123';
      expect(p.value, '123');
      return f.then((val) => expect(val, '123'));
    });
  });

  group('SelectionGroup', () {
    test('adding changes selection', () {
      SelectionGroup<String> group = new SelectionGroup();
      Future f = group.onSelectionChanged.first.then((sel) {
        expect(sel, 'foo');
      });
      group.add('foo');
      return f;
    });

    test('removing changes selection', () {
      SelectionGroup<String> group = new SelectionGroup();
      group.add('foo');
      Future f = group.onSelectionChanged.first.then((sel) {
        expect(sel, null);
      });
      group.remove('foo');
      return f;
    });
  });
}

_checkDiff(List<Edit> edits, Edit expectEdit) {
  expect(edits.length, 1);
  expect(edits.first, expectEdit);
}
