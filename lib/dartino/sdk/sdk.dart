import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/process.dart';

import '../launch_dartino.dart';

/// Abstract SDK implementation used by Dartino.
/// Clients should call <classname>.forPath to instantiate a new SDK
/// then further call [validate] to verify that the SDK is valid.
abstract class Sdk {
  /// The root path of the sdk
  final String sdkRoot;

  Sdk(this.sdkRoot);

  String get name;

  /// Return a string representing the Sdk version, or `null` if unknown.
  Future<String> get version => null;

  /// Return the path to the Dart SDK
  /// that is shipped as part of the Dartino SDK
  String get dartSdkPath => fs.join(sdkRoot, 'internal', 'dart-sdk');

  /// Return the path to the root directory of the samples
  /// or `null` if none.
  String get samplesRoot;

  /// Create a new project at the specified location.
  /// Return a [Future] that indicates whether the project was created.
  Future<bool> createNewProject(String projectPath);

  /// Execute the given SDK binary (a command in the `bin/` folder). [cwd] can
  /// be either a [String] or a [Directory].
  ProcessRunner execBin(String binName, List<String> args,
      {cwd, bool startProcess: true}) {
    if (cwd is Directory) cwd = cwd.path;
    String osBinName = isWindows ? '${binName}.bat' : binName;
    String command = fs.join(sdkRoot, 'bin', osBinName);

    ProcessRunner runner =
        new ProcessRunner.underShell(command, args: args, cwd: cwd);
    if (startProcess) runner.execStreaming();
    return runner;
  }

  /// Return `true` if the specified file exists in the SDK
  bool existsSync(String relativePosixPath) {
    var path = resolvePath(relativePosixPath);
    return path != null && fs.existsSync(path);
  }

  /// Return a path to the `.packages` file used to analyze the specified
  /// project or `null` if none,
  /// where [projDir] may be a [Directory] or a directory path.
  String packageRoot(projDir);

  /// Compile, deploy, and launch the specified application.
  /// Return a [Future] that completes when the application has been launched.
  Future launch(DartinoLaunch launch);

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
        defaultText: fs.join(fs.homedir, relPath), selectLastWord: true);
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

  /// If the user has not already choosen to opt into (or out of) analytics
  /// then prompt the user to do so.
  void promptOptIntoAnalytics();

  /// Show documentation for the installed SDK.
  void showDocs();
}
