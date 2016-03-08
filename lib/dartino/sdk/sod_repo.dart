import 'dart:async';

import 'package:atom/node/fs.dart';

import '../../atom.dart';
import '../dartino_util.dart';
import '../device/device.dart';
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

  String get name => 'SOD repository';

  String get sodUtil => resolvePath('dart/bin/sod.dart');

  /// Compile the application and return the path of the binary to deploy.
  /// If there is a problem, notify the user and return `null`.
  Future<String> compile(DartinoLaunch launch) async {
    String srcPath = launch.primaryResource;
    String dstPath = srcPath.substring(0, srcPath.length - 5) + '.snap';

    int exitCode = await launch.run('make',
        args: [dstPath],
        cwd: sdkRoot,
        isLast: false,
        message: 'Building $srcPath ...');
    if (exitCode != 0) {
      atom.notifications.addError('Failed to compile application',
          detail: 'Failed to compile.\n'
              '$srcPath\n'
              'See console for more.');
      return null;
    }
    return dstPath;
  }

  @override
  Future launch(DartinoLaunch launch) async {
    Device device = await Device.forLaunch(launch);
    if (device == null) return;
    device.launchSOD(this, launch);
  }

  @override
  String packageRoot(projDir) {
    if (projDir == null) return null;
    String localSpecFile = fs.join(projDir, '.packages');
    if (fs.existsSync(localSpecFile)) return localSpecFile;
    return resolvePath('third_party/dartino//internal/dartino-sdk.packages');
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
