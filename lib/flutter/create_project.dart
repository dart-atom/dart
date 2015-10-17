library atom.flutter.create_project;

import 'dart:async';

import 'package:haikunator/haikunator.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../impl/pub.dart';
import '../state.dart';
import '../utils.dart';

class CreateProjectManager implements Disposable {
  Disposables disposables = new Disposables();

  CreateProjectManager() {
    disposables.add(atom.commands
        .add('atom-workspace', 'dartlang:create-flutter-project', _createProject));
  }

  void _createProject(_) {
    if (!sdkManager.hasSdk) {
      sdkManager.showNoSdkMessage(messagePrefix: 'Unable to create project');
      return;
    }

    String root = atom.config.getValue('core.projectHome');
    if (root.endsWith('github')) {
      root = root.substring(0, root.length - 6) + 'flutter';
    }
    String projectPath = "${root}${separator}${Haikunator.haikunate(delimiter: '_')}";
    String _response;

    PubAppGlobal flutter = new PubApp.global('flutter');

    // Install `flutter` if it is not installed or there is an update available.
    Future f = flutter.installIfUpdateAvailable();

    promptUser('Enter the path to the project to create:',
        defaultText: projectPath,
        selectLastWord: true).then((String response) {
      _response = response;
      if (_response != null) return f;
    }).then((_) {
      if (_response != null) {
        return flutter.run(
            args: ['init', '--out', _response],
            title: 'Creating Flutter Project');
      }
    }).then((_) {
      if (_response != null) {
        atom.project.addPath(_response);
        String path = join(_response, 'lib', 'main.dart');
        atom.workspace.open(path).then((TextEditor editor) {
          // Focus the file in the files view 'tree-view:reveal-active-file'.
          atom.commands.dispatch(
              atom.views.getView(editor), 'tree-view:reveal-active-file');
        });
      }
    });
  }

  void dispose() => disposables.dispose();
}
