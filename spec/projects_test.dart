import 'package:atom_dartlang/projects.dart';
import 'package:atom/node/fs.dart';

import '_spec/test.dart';

void register() => registerSuite(new ProjectsTest());

class ProjectsTest extends TestSuite {
  Map<String, Test> getTests() => {
    // 'isDartBuildFile_findsProject': isDartBuildFile_findsProject,
    'isDartBuildFile_noFalsePositive': isDartBuildFile_noFalsePositives
  };

  isDartBuildFile_findsProject() {
    String path = _createTempFile('BUILD', '\n/dart/build_defs\n');
    expect(isDartBuildFile(path), true);

    path = _createTempFile('BUILD', '\ndart_library(\n');
    expect(isDartBuildFile(path), true);

    path = _createTempFile('BUILD', '\ndart_analyzed_library\n');
    expect(isDartBuildFile(path), true);
  }

  isDartBuildFile_noFalsePositives() {
    String path = _createTempFile('BUILD', '\ndarty\n');
    expect(isDartBuildFile(path), false);
  }
}

String _createTempFile(String name, String contents) {
  String path = fs.join(fs.tmpdir, name);
  fs.writeFileSync(path, contents);
  return path;
}
