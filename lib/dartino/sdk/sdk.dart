import 'dart:async';

import 'package:atom/node/fs.dart';

import '../../atom.dart';
import '../../atom_utils.dart';

/// Abstract SDK implementation shared by Dartino and SOD.
/// Clients should call <classname>.forPath to instantiate a new SDK
/// then further call [validate] to verify that the SDK is valid.
abstract class Sdk {
  /// Prompt the user for and return a location to install the SDK.
  /// The default text will be the user's home directory plus [relPosixPath]
  /// where [relPosixPath] is translated into an OS specific path.
  /// If the selected directory already exists,
  /// then notify the user an return `null`.
  static Future<String> promptInstallPath(
      String sdkName, String relPosixPath) async {
    var relPath = relPosixPath.replaceAll('/', fs.separator);
    String path = await promptUser('Enter $sdkName installation path',
        defaultText: fs.join(homedir(), relPath), selectLastWord: true);
    if (path == null) return null;
    path = path.trim();
    if (path.isEmpty) return null;
    if (fs.existsSync(path)) {
      atom.notifications.addError('Invalid installation location',
          detail: 'The installation directory already exists.\n$path');
      return null;
    }
    return path;
  }
}
