/// A library for executing unit tests.
library atom.tests;

import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';

import '../atom.dart';
import '../projects.dart';
import '../state.dart';
import 'pub.dart';

class TestManager implements Disposable {
  Disposables disposables = new Disposables();

  TestManager() {
    disposables.add(
      atom.commands.add('atom-workspace', '${pluginId}:run-tests', _runTests)
    );
  }

  void _runTests(AtomEvent event) {
    TextEditor editor = atom.workspace.getActiveTextEditor();
    if (editor == null || editor.getPath() == null) return;

    String path = editor.getPath();
    DartProject project = projectManager.getProjectFor(path);

    if (project == null) {
      atom.notifications.addWarning('Unable to run tests - no Dart project selected.');
      return;
    }

    PubAppLocal testApp = new PubAppLocal('test', project.path);
    testApp.run(
      title: 'Running ${project.name} tests',
      args: ['-rexpanded', '--no-color']
    ).then((result) {
      print(result);
    });
  }

  void dispose() => disposables.dispose();
}
