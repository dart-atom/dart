
import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:haikunator/haikunator.dart';

import '../projects.dart';
import '../state.dart';
import 'flutter.dart';
import 'flutter_connect.dart';
import 'flutter_devices.dart';
import 'flutter_sdk.dart';

FlutterSdkManager _flutterSdk = deps[FlutterSdkManager];

class FlutterToolsManager implements Disposable {
  Disposables disposables = new Disposables();

  FlutterConnectManager connectManager;

  FlutterToolsManager() {
    if (Flutter.hasFlutterPlugin()) {
      disposables.add(atom.commands.add(
        'atom-workspace',
        'flutter:screenshot',
        _screenshot
      ));
      disposables.add(atom.commands.add(
        'atom-workspace',
        'flutter:create-project',
        _createProject
      ));
      disposables.add(atom.commands.add(
        'atom-workspace',
        'flutter:doctor',
        _doctor
      ));
      disposables.add(atom.commands.add(
        'atom-workspace',
        'flutter:upgrade',
        _upgrade
      ));
      disposables.add(atom.commands.add(
        'atom-workspace',
        'flutter:connect-remote-debugger',
        _connect
      ));

      connectManager = new FlutterConnectManager();
      disposables.add(connectManager);
    }
  }

  void _screenshot(AtomEvent _) {
    DartProject project = projectManager.getProjectFor(
      atom.workspace.getActiveTextEditor()?.getPath());

    if (project == null) {
      atom.notifications.addWarning('No active project.');
      return;
    }

   // Find the currently selected device.
   FlutterDeviceManager deviceManager = deps[FlutterDeviceManager];
   Device device = deviceManager.currentSelectedDevice;

   // flutter screenshot [-d device.id]
   FlutterTool flutter = _flutterSdk.sdk.flutterTool;
   flutter.runInJob(device == null ? ['screenshot'] : ['screenshot', '-d', device.id],
     title: 'Running Flutter screenshot…',
     cwd: project.directory.path
   );
  }

  void _createProject(AtomEvent _) {
    if (!_flutterSdk.hasSdk) {
      _flutterSdk.showInstallationInfo();
      return;
    }

    String projectName = Haikunator.haikunate(delimiter: '_');
    String parentPath = fs.dirname(_flutterSdk.sdk.path);
    String projectPath = fs.join(parentPath, projectName);

    String _response;
    FlutterTool flutter = _flutterSdk.sdk.flutterTool;

    promptUser(
      'Enter the path to the project to create:',
      defaultText: projectPath,
      selectLastWord: true
    ).then((String response) {
      _response = response;

      if (_response != null) {
        return flutter.runInJob(
          ['create',  _response], title: 'Creating Flutter Project'
        );
      }
    }).then((_) {
      if (_response != null) {
        atom.project.addPath(_response);
        String path = fs.join(_response, 'lib', 'main.dart');
        atom.workspace.open(path).then((TextEditor editor) {
          // Focus the file in the files view 'tree-view:reveal-active-file'.
          atom.commands.dispatch(
              atom.views.getView(editor), 'tree-view:reveal-active-file');
        });
      }
    });
  }

  void _upgrade(AtomEvent _) {
    if (!_flutterSdk.hasSdk) {
      _flutterSdk.showInstallationInfo();
      return;
    }

    TextEditor editor = atom.workspace.getActiveTextEditor();
    if (editor == null) {
      atom.notifications.addWarning('No active editor.');
      return;
    }

    DartProject project = projectManager.getProjectFor(editor.getPath());
    if (project == null) {
      atom.notifications.addWarning('The current project is not a Dart project.');
      return;
    }

    atom.workspace.saveAll();

    FlutterTool flutter = _flutterSdk.sdk.flutterTool;
    flutter.runInJob(['upgrade'],
      title: 'Running Flutter upgrade…',
      cwd: project.directory.path
    );
  }

  void _doctor(AtomEvent _) {
    if (!_flutterSdk.hasSdk) {
      _flutterSdk.showInstallationInfo();
      return;
    }

    FlutterTool flutter = _flutterSdk.sdk.flutterTool;

    flutter.runInJob(['doctor'],
      title: 'Running Flutter doctor…',
      cwd: _flutterSdk.sdk.path
    );
  }

  void _connect(AtomEvent _) {
    if (!_flutterSdk.hasSdk) {
      _flutterSdk.showInstallationInfo();
      return;
    }

    connectManager.showConnectDialog();
  }

  void dispose() => disposables.dispose();
}
