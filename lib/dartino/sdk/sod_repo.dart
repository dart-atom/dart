import 'dart:async';

import 'package:atom/node/fs.dart';

import '../../atom.dart';
import '../dartino_util.dart';
import '../launch_dartino.dart';
import 'sdk.dart';

/// The SOD repository as an SDK
class SodRepo extends Sdk {
  /// Return a new instance if an SDK could exist at the given [path]
  /// or `null` if not. Clients should call [validate] on any returned sdk
  /// to ensure that it is a valid SDK.
  static SodRepo forPath(String path) {
    var sdk = new SodRepo(path);
    return sdk.existsSync('third_party/openocd/README.md') ? sdk : null;
  }

  /// Prompt the user for where to install a new SDK, then do it.
  static Future promptInstall([_]) async {
    // String path =
    await Sdk.promptInstallPath('SOD repository', 'sod/repo');
    atom.notifications.addError('Not implemented yet');
  }

  SodRepo(String sdkRoot) : super(sdkRoot);

  @override
  Future launch(DartinoLaunch launch) async {
    atom.notifications.addError('Not implemented yet');
  }

  @override
  String packageRoot(projDir) {
    return projDir != null ? fs.join(projDir, '.packages') : null;
  }

  @override
  bool validate({bool quiet: false}) {
    if (!existsSync('third_party/lk/platform/stm32f7xx/init.c')) {
      if (!quiet) {
        dartino.promptSetSdk('Invalid SOD repository specified.',
            detail: 'It appears that SOD was installed'
                ' using git clone rather than gclient.');
      }
      return false;
    }
    return true;
  }
}
