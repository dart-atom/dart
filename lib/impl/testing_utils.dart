
/// Return the list of possible test paths. The given [path] must be in the
/// `lib/` directory.
List<String> getPossibleTestPaths(String path, String separator) {
  assert(separator.length == 1);

  if (!path.startsWith('lib${separator}')) return [];
  path = path.substring(4);

  List<String> result = [];

  // Remove '.dart'; add '_test.dart'.
  path = path.substring(0, path.length - 5) + '_test.dart';

  // Look for test/path/file_test.dart.
  String testPath = 'test' + separator + path;
  result.add(testPath);

  // Look for test/path-w/o-src/file_test.dart.
  if (path.startsWith('src${separator}')) {
    path = path.substring(4);
    testPath = 'test' + separator + path;
    result.add(testPath);
  }

  // Look for test/file_test.dart.
  if (path.contains('/')) {
    testPath = 'test' + separator + _basename(path, separator: separator);
    result.add(testPath);
  }

  return result;
}

String _basename(String name, { String separator}) {
  int index = name.lastIndexOf(separator);
  return index == -1 ? name : name.substring(index + 1);
}
