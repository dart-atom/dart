// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.dependencies_test;

import 'package:atom_dartlang/dartino/dartino_util.dart';
import 'package:test/test.dart';

main() => defineTests();

defineTests() {
  group('dartino', () {
    group('packages file', () {
      test('random', () {
        expect(containsDartinoReferences(null, null), isFalse);
        expect(containsDartinoReferences(null, ''), isFalse);
        expect(containsDartinoReferences('', null), isFalse);
        expect(containsDartinoReferences(null, ''), isFalse);
        expect(containsDartinoReferences(null, 'foo'), isFalse);
        expect(containsDartinoReferences('foo', 'bar'), isFalse);
        expect(containsDartinoReferences('asd aesfse', 'asd'), isFalse);
      });
      test('non Dartino package file', () {
        bool actual = containsDartinoReferences(
            '''# Generated by pub
analyzer:file:///Users/foo/bar/lib/
ansicolor:file:///Users/foo/two/lib/
args:file:///Users/foo/three/lib/
async:file:///Users/foo/four/lib/
''',
            '/path/to/dartino-sdk');
        expect(actual, isFalse);
      });
      test('Dartino package file', () {
        bool actual = containsDartinoReferences(
            '''# Generated by pub
analyzer:file:///Users/foo/bar/lib/
ansicolor:file:///path/to/dartino-sdk/pkg/dartino/lib/
args:file:///Users/foo/three/lib/
async:file:///Users/foo/four/lib/
''',
            '/path/to/dartino-sdk');
        expect(actual, isTrue);
      });
    });
  });
}
