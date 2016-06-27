import 'package:atom_dartlang/impl/testing_utils.dart';
import 'package:test/test.dart';

main() => defineTests();

defineTests() {
  group('test_utils', () {
    test('getPossibleTestPaths', () {
      expect(getPossibleTestPaths('bin/foo.dart', '/'), equals([]));
      expect(
        getPossibleTestPaths('lib/foo.dart', '/'),
        equals(['test/foo_test.dart'])
      );
      expect(
        getPossibleTestPaths('lib/bar/foo.dart', '/'),
        equals(['test/bar/foo_test.dart', 'test/foo_test.dart'])
      );
      expect(
        getPossibleTestPaths('lib/src/foo.dart', '/'),
        equals(['test/src/foo_test.dart', 'test/foo_test.dart'])
      );
      expect(
        getPossibleTestPaths('lib/src/bar/foo.dart', '/'),
        equals(['test/src/bar/foo_test.dart', 'test/bar/foo_test.dart', 'test/foo_test.dart'])
      );
    });
  });
}
