import 'dart:async';
import 'dart:convert';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/process.dart';
import 'package:atom/node/shell.dart';
import 'package:atom_dartlang/jobs.dart';
import 'package:logging/logging.dart';

import '../../impl/pub.dart' show dotPackagesFileName;
import '../device/device.dart';
import '../launch_dartino.dart';
import 'sdk.dart';

class DartinoSdk extends Sdk {
  /// Return a new instance if an SDK could exist at the given [path]
  /// or `null` if not. Clients should call [validate] on any returned sdk
  /// to ensure that it is a valid SDK.
  static DartinoSdk forPath(String path) {
    var sdk = new DartinoSdk(path);
    return fs.existsSync(sdk.dartinoBinary) ? sdk : null;
  }

  /// Prompt the user for where to install a new SDK, then do it.
  static Future promptInstall([_]) async {
    //TODO(danrubel) add Windows support
    if (isWindows) {
      atom.notifications.addError('Windows not supported yet');
      return;
    }

    // Start the download
    Future<String> download = _downloadSdkZip();

    // Prompt the user then wait for download to complete
    String path = await Sdk.promptInstallPath('Dartino SDK', 'dartino-sdk');
    String tmpSdkDir = await download;
    if (tmpSdkDir == null) return;

    // Install the new SDK
    if (path != null) {
      var runner = new ProcessRunner('mv', args: [tmpSdkDir, path]);
      var result = await runner.execSimple();
      if (result.exit != 0) {
        atom.notifications.addError('Failed to install Dartino SDK',
            detail: 'exitCode: ${result.exit}'
                '\n${result.stderr}\n${result.stdout}');
        return;
      }
      atom.config.setValue('dartino.dartinoPath', path);
      atom.notifications.addSuccess('Dartino SDK installed', detail: path);
    }

    // Cleanup
    var runner = new ProcessRunner('rm', args: ['-r', (fs.dirname(tmpSdkDir))]);
    runner.execSimple();
  }

  DartinoSdk(String sdkRoot) : super(sdkRoot);

  /// Return the path to the dartino command line binary
  String get dartinoBinary => resolvePath('bin/dartino');

  String get name => 'Dartino SDK';

  String get samplesRoot => resolvePath('samples');

  @override
  Future<String> get version async {
    try {
      return await exec(dartinoBinary, ['--version']);
    } catch (_) {
      return null;
    }
  }

  /// Compile the application and return a path to the compiled binary.
  /// If there is a problem, notify the user and return `null`.
  Future<String> compile(DartinoLaunch launch) async {
    await _validateLocalSettingsFile(this, launch);
    String srcPath = launch.primaryResource;
    int exitCode = await launch.run(dartinoBinary,
        args: ['compile', srcPath],
        cwd: fs.dirname(srcPath),
        message: 'Compiling $srcPath',
        isLast: false);
    if (exitCode != 0) {
      atom.notifications.addError('Compilation Failed',
          detail:
              '$srcPath\nexitCode : $exitCode\nSee console for more detail');
      return null;
    }
    return srcPath.substring(0, srcPath.length - 5) + '.bin';
  }

  @override
  Future<bool> createNewProject(String projectPath) {
    // TODO(danrubel) get list of supported boards
    // and prompt user for which board they would like to create a project.
    // If there is a connected board then make that the default.
    String boardName = 'stm32f746g-discovery';

    // Create the project using the dartino cmdline utility
    return new DartinoCmd(this, 'Creating ${fs.basename(projectPath)}',
            ['create', 'project', projectPath, 'for', boardName],
            // Do not display a completion message unless there is an error
            // because the caller should open the new project.
            quiet: true)
        .start();
  }

  @override
  Future launch(DartinoLaunch launch) async {
    if (!await _installAdditionalTools(this, launch)) return;
    _validateLocalSettingsFile(this, launch);
    Device device = await Device.forLaunch(this, launch);
    if (device == null) {
      launch.launchTerminated(-1, quiet: true);
      return;
    }
    device.launchDartino(this, launch);
  }

  @override
  String packageRoot(projDir) {
    if (projDir == null) return null;
    String localSpecFile = fs.join(projDir, dotPackagesFileName);
    if (fs.existsSync(localSpecFile)) return localSpecFile;
    return resolvePath('internal/dartino-sdk.packages');
  }

  @override
  bool validate({bool quiet: false}) => true;

  @override
  Future promptOptIntoAnalytics() async {
    if (_promptOptIntoAnalyticsStarted) return;
    // Determine whether the user has already opted in or out.
    ProcessRunner runner =
        execBin('dartino', ['x-should-prompt-analytics'], startProcess: false);
    ProcessResult result = await runner.execSimple();
    if (result.exit != 0 || result.stdout?.trim() != 'true') return;
    _promptOptIntoAnalyticsStarted = true;

    Notification notification;
    void recordChoice(String verb) {
      execBin('dartino', [verb, 'analytics']);
      notification.dismiss();
    }
    void optIn() => recordChoice('enable');
    void optOut() => recordChoice('disable');

    notification = atom.notifications.addInfo(
        'Welcome to Dartino! '
        'We collect anonymous usage statistics and crash reports '
        'in order to improve the tool (see http://goo.gl/27JjhU for details).\n'
        ' \n'
        'Would you like to opt-in to help us improve Dartino?',
        dismissable: true,
        buttons: [
          new NotificationButton('Yes', optIn),
          new NotificationButton('No', optOut)
        ]);
  }

  @override
  void showDocs() {
    var uri = new Uri.file(fs.join(sdkRoot, 'docs', 'index.html'));
    shell.openExternal(uri.toString());
  }
}

/// A flag indicating whether the user has already been prompted to opt into
/// analytics during this session.
bool _promptOptIntoAnalyticsStarted = false;

/// Start downloading the latest Dartino SDK and return a [Future]
/// that completes with a path to the downloaded and unzipped SDK directory.
Future<String> _downloadSdkZip() async {
  String zipName;
  if (isMac) zipName = 'dartino-sdk-macos-x64-release.zip';
  if (isLinux) zipName = 'dartino-sdk-linux-x64-release.zip';
  //TODO(danrubel) add Windows support
  //TODO(danrubel) extract this into a reusable class for use by Flutter

  // Download the zip file
  var dirPath = fs.join(fs.tmpdir, 'dartino-download');
  var dir = new Directory.fromPath(dirPath);
  if (!dir.existsSync()) await dir.create();
  var zipPath = fs.join(dirPath, zipName);
  if (!new File.fromPath(zipPath).existsSync()) {
    var url = 'http://gsdview.appspot.com/dartino-archive/channels/'
        'dev/release/latest/sdk/$zipName';
    var info = atom.notifications.addInfo('Downloading $zipName');
    var runner =
        new ProcessRunner('curl', args: ['-s', '-L', '-O', url], cwd: dirPath);
    var result = await runner.execSimple();
    info.dismiss();
    if (result.exit != 0) {
      atom.notifications.addError('Failed to download $zipName',
          detail: 'exitCode: ${result.exit}'
              '\n${result.stderr}\n${result.stdout}');
      return null;
    }
  }

  // Unzip the zip file into a temporary location
  var sdkPath = fs.join(dirPath, 'dartino-sdk');
  if (!new Directory.fromPath(sdkPath).existsSync()) {
    var runner =
        new ProcessRunner('unzip', args: ['-q', zipName], cwd: dirPath);
    var result = await runner.execSimple();
    if (result.exit != 0) {
      atom.notifications.addError('Failed to unzip $zipName',
          detail: 'exitCode: ${result.exit}'
              '\n${result.stderr}\n${result.stdout}');
      return null;
    }
  }
  return sdkPath;
}

/// Return a [Future] that completes with `true`
/// once additional Dartino tools have been downloaded and installed.
/// If there is a problem, notify the user and complete the future with `false`.
Future _installAdditionalTools(DartinoSdk sdk, DartinoLaunch launch) async {
  // Check to see if tools have already been downloaded
  if (sdk.existsSync('tools/gcc-arm-embedded/bin/arm-none-eabi-gcc')) {
    return true;
  }

  // Launch an external process to download the additional tools
  Notification msg = atom.notifications.addInfo('Downloading Tools...',
      detail: 'See console for more detail...', dismissable: true);
  NotificationHelper helper = new NotificationHelper(msg.view);
  helper.setRunning();
  int exitCode = await launch.run(sdk.dartinoBinary,
      args: ['x-download-tools'],
      cwd: sdk.sdkRoot,
      message: 'Downloading additional tools into ${sdk.sdkRoot} ...',
      isLast: false, onStdout: (str) {
    str = str.replaceAll('Download', '\nDownload');
    launch.pipeStdio(str, subtle: true);
  });
  if (exitCode != 0) {
    helper.showError();
    helper.appendText('\nexitCode : $exitCode');
    return false;
  }
  helper.showSuccess();
  helper.appendText('\nDownload complete');
  launch.pipeStdio('Download complete\n');
  return true;
}

/// Validate the local.dartino-settings file in the user's home directory.
Future _validateLocalSettingsFile(DartinoSdk sdk, DartinoLaunch launch) async {
  //TODO(danrubel) move this validation and notification into cmdline tool
  try {
    var path = fs.join(fs.homedir, 'local.dartino-settings');
    if (!fs.existsSync(path)) return;
    var file = new File.fromPath(path);
    var content = await file.read();
    Map json = JSON.decode(content);
    String pkgsUri = json['packages'];
    if (pkgsUri == null || !pkgsUri.startsWith('file://')) return;
    var pkgsPath = pkgsUri.substring(7);
    if (!fs.existsSync(pkgsPath)) {
      launch.pipeStdio(
          'WARNING: the dartino settings file: $path\n'
          'references non-existing packages files: $pkgsPath\n'
          'Either fix the path in the file'
          ' or delete the file to have it recreated\n',
          error: true);
      return;
    }
  } catch (e, s) {
    new Logger('DartinoSdk').info('validate local settings exception', e, s);
  }
}

/// Launch and monitor the Dartino cmdline utility,
/// reporting progress and result to the user.
class DartinoCmd extends Job {
  final DartinoSdk sdk;
  final List<String> cmd;

  // Override superclass getter to be quiet based upon constructor settings.
  final bool quiet;

  DartinoCmd(this.sdk, String name, this.cmd, {this.quiet: false})
      : super(name);

  Future<bool> start() =>
      schedule().then((JobStatus status) => status.isOk && status.result == 0);

  @override
  Future run() {
    return new ProcessNotifier(name).watch(sdk.execBin('dartino', cmd));
  }
}
