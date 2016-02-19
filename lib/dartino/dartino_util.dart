library atom.dartino.dartino_util;

import '../atom.dart';
import '../atom_utils.dart';

const _pluginId = 'dartino';

final _Dartino dartino = new _Dartino();

class _Dartino {
  String sdkPath() {
    var sdkPath = atom.config.getValue('$_pluginId.dartinoPath');
    return (sdkPath is String) ? sdkPath : '';
  }

  bool hasSdk() => sdkPath().isNotEmpty;

  bool isProject(projDir) =>
      hasSdk() && existsSync(join(projDir, 'dartino.yaml'));

  /// If the project does *not* contain a .packages file
  /// then return the SDK defined package spec file
  /// so that it can be passed to the analysis server for this project
  /// otherwise return `null`.
  String packageRoot(projDir) {
    if (existsSync(join(projDir, '.packages'))) return null;
    return join(sdkPath(), 'internal', 'dartino-sdk.packages');
  }
}
