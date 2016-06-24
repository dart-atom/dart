/// A library for executing unit tests.
library atom.tests;

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:atom/utils/disposable.dart';

import '../flutter/flutter_sdk.dart';
import '../launch/launch.dart';
import '../projects.dart';
import '../state.dart';

FlutterSdkManager _flutterSdk = deps[FlutterSdkManager];

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
  }

  bool isRunnableTest(String path, { bool allowWithoutTestName: false }) {
    if (!isDartFile(path)) return false;

    if (!allowWithoutTestName) {
      if (!path.endsWith('_test.dart')) return false;
    }

    DartProject project = projectManager.getProjectFor(path);
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

  void dispose() => disposables.dispose();
}

abstract class TestRunner {
  bool canRun(DartProject project, String path);
  Launch run(DartProject project, String path);
}

class FlutterTestRunner extends TestRunner {
  bool canRun(DartProject project, String path) {
    return project.isFlutterProject() && project.importsPackage('test');
  }

  Launch run(DartProject project, String path) {
    // TODO(devoncarew): Add an option to send in the `--merge-coverage` flag.

    String relativePath = project.getRelative(path);

    ProcessRunner runner = new ProcessRunner(
      _flutterSdk.sdk.flutterToolPath,
      args: ['--no-color', 'test', relativePath],
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
