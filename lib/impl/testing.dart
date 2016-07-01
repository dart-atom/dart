/// A library for executing unit tests.
library atom.testing;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:atom/utils/disposable.dart';

import '../flutter/flutter_sdk.dart';
import '../launch/launch.dart';
import '../projects.dart';
import '../state.dart';
import 'testing_utils.dart';

FlutterSdkManager _flutterSdk = deps[FlutterSdkManager];

final String _sep = fs.separator;

class TestManager implements Disposable {
  Disposables disposables = new Disposables();

  List<TestRunner> runners = [
    new FlutterTestRunner(),
    new TestPackageTestRunner(),
    new CliTestRunner()
  ];

  TestManager() {
    disposables.add(
      atom.commands.add('atom-workspace', '${pluginId}:run-tests', _runTests)
    );
    disposables.add(
      atom.commands.add('atom-workspace', '${pluginId}:create-test', _createTest)
    );
  }

  bool isRunnableTest(String path, { bool allowWithoutTestName: false }) {
    if (!isDartFile(path)) return false;
    if (path.endsWith('_test.dart')) return true;

    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return false;

    path = _findAssociatedTest(project, path);

    if (!allowWithoutTestName) {
      if (!path.endsWith('_test.dart')) {
        // Support `all.dart` files in the test directory.
        bool isAllDart = path.contains('${_sep}test${_sep}') && path.endsWith('${_sep}all.dart');
        if (!isAllDart) return false;
      }
    }

    return runners.any((TestRunner runner) => runner.canRun(project, path));
  }

  Launch runTestFile(String path, { bool allowWithoutTestName: false }) {
    if (!isDartFile(path)) {
      atom.notifications.addWarning(
        'Unable to run tests - not a Dart file.',
        description: path
      );
      return null;
    }

    if (!isRunnableTest(path, allowWithoutTestName: allowWithoutTestName)) {
      atom.notifications.addWarning(
        'Unable to run tests - not a valid test file.',
        description: path
      );
      return null;
    }

    atom.workspace.saveAll();

    DartProject project = projectManager.getProjectFor(path);
    path = _findAssociatedTest(project, path);

    for (TestRunner runner in runners) {
      if (runner.canRun(project, path)) {
        return runner.run(project, path);
      }
    }

    atom.notifications.addWarning('Unable to run test file.', description: path);
    return null;
  }

  void _runTests(AtomEvent event) {
    String path = atom.workspace.getActiveTextEditor()?.getPath();
    DartProject project = projectManager.getProjectFor(path);

    if (project == null) {
      atom.notifications.addWarning('Unable to run tests - no Dart project selected.');
      return;
    }

    runTestFile(path, allowWithoutTestName: true);
  }

  /// Finds the test file most closely associted with this test. If the given
  /// path is a test file itself, or not associated test file is found, the
  /// original path is returned.
  String _findAssociatedTest(DartProject project, String path) {
    if (path == null || path.endsWith('_test.dart')) return path;

    String prefix = project.path;
    String pathFragment = path.substring(prefix.length + 1);

    for (String fragment in getPossibleTestPaths(pathFragment, fs.separator)) {
      String testPath = fs.join(prefix, fragment);
      if (fs.existsSync(testPath)) {
        return testPath;
      }
    }

    return path;
  }

  Future _createTest([AtomEvent _]) async {
    String path = atom.workspace.getActiveTextEditor()?.getPath();
    if (path == null) {
      atom.notifications.addInfo('No active editor.');
      return;
    }

    DartProject project = projectManager.getProjectFor(path);
    if (project == null) {
      atom.notifications.addInfo('No active Dart project.');
      return;
    }

    if (!isDartFile(path)) {
      atom.notifications.addInfo('Current editor is not a Dart file.', description: path);
      return;
    }

    String pathFragment = project.getRelative(path);

    if (!pathFragment.startsWith('lib${fs.separator}')) {
      atom.notifications.addInfo("This action requires the file to be in the 'lib' folder.");
      return;
    }

    // Remove lib/.
    pathFragment = pathFragment.substring(4);
    String testPath = pathFragment.substring(0, pathFragment.length - 5) + '_test.dart';
    testPath = fs.join(project.path, 'test', testPath);

    if (fs.existsSync(testPath)) {
      atom.workspace.open(testPath);
      return;
    }

    String packageName = project.getSelfRefName();
    String groupName = fs.basename(pathFragment);
    groupName = groupName.substring(0, groupName.length - 5);

    File file = new File.fromPath(testPath);
    file.writeSync('''
import 'package:${packageName}/${pathFragment}';
import 'package:test/test.dart';

main() => defineTests();

defineTests() {
  group('${groupName}', () {
    test('todo', () {
      // TODO: Implement test.

    });
  });
}
''');

    // Delay to make sure the file is written to disk.
    await new Future.delayed(Duration.ZERO);

    atom.workspace.open(testPath).then((_) {
      // Once the file is open, run the tests for it the first time.
      runTestFile(testPath);
    });
  }

  void dispose() => disposables.dispose();
}

abstract class TestRunner {
  bool canRun(DartProject project, String path);
  Launch run(DartProject project, String path);
}

class FlutterTestRunner extends TestRunner {
  bool canRun(DartProject project, String path) {
    return project.importsPackage('flutter') && project.importsPackage('test');
  }

  Launch run(DartProject project, String path) {
    String relativePath = project.getRelative(path);
    List<String> args = ['--no-color', 'test'];
    if (atom.config.getBoolValue('flutter.mergeCoverage'))
      args.add('--merge-coverage');
    args.add(relativePath);

    ProcessRunner runner = new ProcessRunner(
      _flutterSdk.sdk.flutterToolPath,
      args: args,
      cwd: project.path
    );
    String description = 'flutter test ${relativePath}';
    Launch launch = new Launch(launchManager, null, null, relativePath,
      killHandler: () => runner.kill(),
      cwd: project.path,
      title: description
    );
    launchManager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) => launch.pipeStdio(str));
    runner.onStderr.listen((str) => launch.pipeStdio(str, error: true));
    runner.onExit.then((code) => launch.launchTerminated(code));

    return launch;
  }
}

class TestPackageTestRunner extends TestRunner {
  bool canRun(DartProject project, String path) {
    if (project.importsPackage('test')) {
      // Package test doesn't work without symlinked directories.
      return fs.existsSync(fs.join(project.path, 'packages'));
    } else {
      return false;
    }
  }

  Launch run(DartProject project, String path) {
    String relativePath = project.getRelative(path);

    ProcessRunner runner = new ProcessRunner(
      sdkManager.sdk.getToolPath('pub'),
      args: ['run', 'test', '-rexpanded', '--no-color', relativePath],
      cwd: project.path
    );
    String description = 'pub run test ${relativePath}';
    Launch launch = new Launch(launchManager, null, null, relativePath,
      killHandler: () => runner.kill(),
      cwd: project.path,
      title: description
    );
    launchManager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) => launch.pipeStdio(str));
    runner.onStderr.listen((str) => launch.pipeStdio(str, error: true));
    runner.onExit.then((code) => launch.launchTerminated(code));

    return launch;
  }
}

class CliTestRunner extends TestRunner {
  bool canRun(DartProject project, String path) {
    return project.importsPackage('test');
  }

  Launch run(DartProject project, String path) {
    String relativePath = project.getRelative(path);

    ProcessRunner runner = new ProcessRunner(
      sdkManager.sdk.dartVm.path,
      args: [relativePath],
      cwd: project.path
    );
    String description = 'dart ${relativePath}';
    Launch launch = new Launch(launchManager, null, null, relativePath,
      killHandler: () => runner.kill(),
      cwd: project.path,
      title: description
    );
    launchManager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) => launch.pipeStdio(str));
    runner.onStderr.listen((str) => launch.pipeStdio(str, error: true));
    runner.onExit.then((code) => launch.launchTerminated(code));

    return launch;
  }
}
