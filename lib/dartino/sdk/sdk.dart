import 'dart:async';

import 'package:atom/node/fs.dart';

import '../../atom.dart';
import '../../atom_utils.dart';

/// Abstract SDK implementation shared by Dartino and SOD.
/// Clients should call <classname>.forPath to instantiate a new SDK
/// then further call [validate] to verify that the SDK is valid.
abstract class Sdk {
  /// The root path of the sdk
  final String sdkRoot;

  Sdk(this.sdkRoot);

  /// Return `true` if the specified file exists in the SDK
  bool existsSync(String relativePosixPath) {
    var path = resolvePath(relativePosixPath);
    return path != null && fs.existsSync(path);
  }

  /// Return a path to the `.packages` file used to analyze the specified
  /// project or `null` if none,
  /// where [projDir] may be a [Directory] or a directory path.
  String packageRoot(projDir);

  /// Return the absolute OS specific path for the file or directory specified by
  /// [relativePosixPath] in the SDK, or `null` if there is a problem.
  String resolvePath(String relativePosixPath) {
    if (sdkRoot == null || sdkRoot.trim().isEmpty) return null;
    return fs.join(sdkRoot, relativePosixPath.replaceAll('/', fs.separator));
  }

  /// Return `true` if this is a valid SDK installation,
  /// otherwise notify the user of the problem and return `false`.
  /// Set `quiet: true` to supress any user notifications.
  bool validate({bool quiet: false});

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
