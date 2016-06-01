import 'package:atom/atom.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../elements.dart';
import '../launch/launch_configs.dart';
import '../projects.dart';
import '../state.dart';
import 'flutter_daemon.dart';
import 'flutter_devices.dart';
import 'flutter_launch.dart';

final Logger _logger = new Logger('flutter.connect');

/// Connect the tools to a Flutter app that is already running on a device.
class FlutterConnectManager implements Disposable {
  Disposables _disposables = new Disposables();

  ConnectDialog connectDialog;

  void showConnectDialog() {
    if (connectDialog == null) {
      connectDialog = new ConnectDialog();
      _disposables.add(connectDialog);
    }
    connectDialog.show();
  }

  void dispose() => _disposables.dispose();
}

class ConnectDialog implements Disposable {
  TitledModelDialog dialog;
  CoreElement _listGroup;

  ConnectDialog() {
    // TODO(devoncarew): rename the style to something more general like list-dialog
    dialog = new TitledModelDialog('Connect to Flutter App', classes: 'jobs-dialog');
    dialog.content.add([
      div(c: 'select-list')..add([_listGroup = ol(c: 'list-group')])
    ]);
  }

  void _updateApps(List<DiscoveredApp> apps) {
    for (DiscoveredApp app in apps) {
      CoreElement item = li(c: 'job-container')
          ..layoutHorizontal()
          ..add([
            div()
              ..inlineBlock()
              ..flex()
              ..text = app.id
              ..click(() => onClick(app))
          ]);

      _listGroup.add(item);
    }
  }

  void show() {
    _listGroup.clear();
    dialog.show();

    FlutterDaemon daemon = deps[FlutterDaemonManager].daemon;
    String deviceId = deps[FlutterDeviceManager].currentSelectedDevice.id;
    daemon.app.discover(deviceId).then(_updateApps);
  }

  void onClick(DiscoveredApp app) {
    dialog.hide();

    DartProject project = projectManager.getProjectFor(
      atom.workspace.getActiveTextEditor()?.getPath());
    if (project == null) {
      atom.notifications.addWarning('No active project.');
      return;
    }

    List<LaunchConfiguration> configs = project == null ?
        [] : launchConfigurationManager.getConfigsForProject(project.path);

    if (configs.isNotEmpty) {
      FlutterLaunchType launchType = launchManager.getLaunchType('flutter');
      launchType.connectToApp(project, configs.first, app.observatoryPort);
    }
  }

  void dispose() => dialog.dispose();
}
