import 'package:atom/node/fs.dart';

import '../atom.dart';
import 'sdk/dartino_sdk.dart';
import 'sdk/sdk.dart';
import 'sdk/sod_repo.dart';

const _pluginId = 'dartino';

final _Dartino dartino = new _Dartino();

class _Dartino {
  /// Return the device path specified in the settings or an empty string if none.
  String get devicePath {
    var path = atom.config.getValue('$_pluginId.devicePath');
    return (path is String) ? path.trim() : '';
  }

  /// Return the SDK path specified in the settings or an empty string if none.
  String get sdkPath {
    String path = atom.config.getValue('$_pluginId.sdkPath');
    return (path is String) ? path.trim() : '';
  }

  /// Return the SDK associated with the given project
  /// where [projDir] can be either a [Directory] or a directory path.
  /// If there is a problem, then notify the user and return `null`.
  /// Set `quiet: true` to supress any user notifications.
  Sdk sdkFor(projDir, {bool quiet: false}) {
    //TODO(danrubel) cache SDK path in project metadata
    String path = sdkPath;
    if (path.isEmpty) {
      if (!quiet) promptSetSdk('No SDK specified');
      return null;
    }
    Sdk sdk = DartinoSdk.forPath(path);
    if (sdk == null) sdk = SodRepo.forPath(path);
    if (sdk == null) {
      if (!quiet) promptSetSdk('Invalid SDK path specified');
      return null;
    }
    return sdk.validate(quiet: quiet) ? sdk : null;
  }

  bool isProject(projDir) => fs.existsSync(fs.join(projDir, 'dartino.yaml'));

  /// Open the Dartino settings page
  void openSettings([_]) {
    atom.workspace.open('atom://config/packages/dartino');
  }

  /// Prompt the user to change the SDK setting or install a new SDK
  promptSetSdk(String message, {String detail}) {
    atom.notifications.addError(message,
        detail: '${detail != null ? "$detail\n \n" : ""}'
            'Click install to install a new SDK or open the settings\n'
            'to specify the path to an already existing installation.',
        buttons: [
          new NotificationButton('Install', promptInstallSdk),
          new NotificationButton('Open settings', openSettings)
        ]);
  }

  /// Prompt the user which SDK and where to install, then do it.
  void promptInstallSdk([_]) {
    // atom.notifications
    //     .addInfo('Which SDK would you like to install?', buttons: [
    //   new NotificationButton('Dartino', DartinoSdk.promptInstall),
    //   new NotificationButton('SOD', SodRepo.promptInstall)
    // ]);
    DartinoSdk.promptInstall();
  }

  /// Validate the installed SDK if there is one.
  void validateSdk([_]) {
    if (sdkPath.isNotEmpty) {
      var sdk = sdkFor(null);
      if (sdk != null && sdk.validate()) {
        atom.notifications
            .addSuccess('Valid ${sdk.name} detected', detail: sdkPath);
      }
    }
  }
}
