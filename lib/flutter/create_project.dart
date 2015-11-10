library atom.flutter.create_project;

import 'package:haikunator/haikunator.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../state.dart';
import '../utils.dart';
import 'flutter_sdk.dart';

FlutterSdkManager _flutterSdk = deps[FlutterSdkManager];

class CreateProjectManager implements Disposable {
  Disposables disposables = new Disposables();

  CreateProjectManager() {
    disposables.add(atom.commands
        .add('atom-workspace', 'flutter:create-project', _createProject));
  }

  void _createProject(AtomEvent _) {
    if (!_flutterSdk.hasSdk) {
      _flutterSdk.showInstallationInfo();
      return;
    }

    String root = atom.config.getValue('core.projectHome');
    if (root.endsWith('github')) {
      root = root.substring(0, root.length - 6) + 'flutter';
    }
    String projectPath = "${root}${separator}${Haikunator.haikunate(delimiter: '_')}";
    String _response;
    FlutterTool flutter = _flutterSdk.sdk.flutterTool;
    promptUser(
        'Enter the path to the project to create:',
        defaultText: projectPath,
        selectLastWord: true).then((String response) {
      _response = response;

      if (_response != null) {
        return flutter.runInJob(
          ['init', '--out', _response], title: 'Creating Flutter Project');
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
