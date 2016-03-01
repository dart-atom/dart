import 'package:atom/node/fs.dart';

import '../atom.dart';
import 'sdk/dartino_sdk.dart';

const _pluginId = 'dartino';

final _Dartino dartino = new _Dartino();

class _Dartino {
  String sdkPath() {
    var sdkPath = atom.config.getValue('$_pluginId.dartinoPath');
    return (sdkPath is String) ? sdkPath : '';
  }

  bool hasSdk() => sdkPath().isNotEmpty;

  bool isProject(projDir) =>
      hasSdk() && fs.existsSync(fs.join(projDir, 'dartino.yaml'));

  /// If the project does *not* contain a .packages file
  /// then return the SDK defined package spec file
  /// so that it can be passed to the analysis server for this project
  /// otherwise return `null`.
  String packageRoot(projDir) {
    if (fs.existsSync(fs.join(projDir, '.packages'))) return null;
    return fs.join(sdkPath(), 'internal', 'dartino-sdk.packages');
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
}
