import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';
import 'package:logging/logging.dart';

import '../elements.dart';
import '../launch/launch.dart';
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
  CoreElement itemCount;

  ConnectDialog() {
    dialog = new TitledModelDialog('Connect Debugger to Remote Flutter App:', classes: 'list-dialog');
    dialog.content.add([
      div(c: 'select-list')..add([_listGroup = ol(c: 'list-group')]),
      itemCount = div(text: 'Looking for apps…')
    ]);
  }

  void show() {
    _listGroup.clear();
    dialog.show();

    FlutterDaemon daemon = deps[FlutterDaemonManager].daemon;
    FlutterDeviceManager flutterDeviceManager = deps[FlutterDeviceManager];

    if (flutterDeviceManager.currentSelectedDevice == null) {
      dialog.hide();
      atom.notifications.addInfo('No Flutter devices found.');
      return;
    }

    String deviceId = flutterDeviceManager.currentSelectedDevice.id;

    DaemonRequestJob job = new DaemonRequestJob('Discovering Flutter Apps', () {
      itemCount.text = 'Looking for apps…';

      return daemon.app.discover(deviceId)
        .then(_updateApps)
        .catchError((e) {
          itemCount.text = 'No apps detected.';
          throw e;
        });
    });
    job.schedule();
  }

  void _handleAppClick(DiscoveredApp app) {
    dialog.hide();

    DartProject project = projectManager.getProjectFor(
      atom.workspace.getActiveTextEditor()?.getPath());
    if (project == null) {
      atom.notifications.addWarning('No active project.');
      return;
    }

    FlutterLaunchType launchType = launchManager.getLaunchType('flutter');
    List<LaunchConfiguration> configs = project == null ?
        [] : launchConfigurationManager.getConfigsForProject(project.path);

    if (configs.isNotEmpty) {
      launchType.connectToApp(project, configs.first, app.observatoryPort);
    } else {
      // Find lib/main.dart; create a launch config for it.
      String mainPath = fs.join(project.path, 'lib/main.dart');
      if (fs.existsSync(mainPath)) {
        LaunchData data = new LaunchData(fs.readFileSync(mainPath));

        if (launchType.canLaunch(project.path, data)) {
          LaunchConfiguration config = launchConfigurationManager.createNewConfig(
            project.path,
            launchType.type,
            'lib/main.dart',
            launchType.getDefaultConfigText()
          );
          launchType.connectToApp(project, config, app.observatoryPort);
        } else {
          atom.notifications.addWarning('The current project is not a runnable Flutter project.');
        }
      } else {
        atom.notifications.addWarning('The current project is not a runnable Flutter project.');
      }
    }
  }

  void _updateApps(List<DiscoveredApp> apps) {
    for (DiscoveredApp app in apps) {
      CoreElement item = li(c: 'item-container select-item')
        ..layoutHorizontal()
        ..add([
          div()
            ..inlineBlock()
            ..flex()
            ..text = app.id
            ..click(() => _handleAppClick(app))
        ]);
      _listGroup.add(item);
    }

    if (apps.isEmpty) {
      itemCount.text = 'No apps detected.';
    } else {
      itemCount.text = '${apps.length} ${pluralize('app', apps.length)} detected.';
    }
  }

  void dispose() => dialog.dispose();
}
