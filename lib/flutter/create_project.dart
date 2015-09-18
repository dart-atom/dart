library atom.flutter.create_project;

import 'dart:async';

import 'package:haikunator/haikunator.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../utils.dart';
import '../impl/pub.dart';

class CreateProjectManager implements Disposable {
  Disposables disposables = new Disposables();

  CreateProjectManager() {
    disposables.add(atom.commands
        .add('atom-workspace', 'dartlang:create-flutter-project', _createProject));
  }

  void _createProject(_) {
    String root = atom.config.getValue('core.projectHome');
    if (root.endsWith('github')) {
      root = root.substring(0, root.length - 6) + 'flutter';
    }
    String projectPath = "${root}${separator}${Haikunator.haikunate(delimiter: '_')}";
    String _response;

    PubApp skyTools = new PubApp.global('sky_tools');
    Future f = skyTools.isInstalled().then((installed) {
      if (!installed) return skyTools.install();
    });

    promptUser('Enter the path to the project to create:',
        defaultText: projectPath,
        selectLastWord: true).then((String response) {
      _response = response;
      if (_response != null) return f;
    }).then((_) {
      if (_response != null) {
        return skyTools.run(args: ['init', '--out', _response]);
      }
    }).then((_) {
      if (_response != null) {
        atom.notifications.addSuccess('Created ${basename(_response)}!');
        atom.project.addPath(_response);
        atom.workspace.open(join(_response, 'lib', 'main.dart'));
      }
    });
  }

  void dispose() => disposables.dispose();
}
