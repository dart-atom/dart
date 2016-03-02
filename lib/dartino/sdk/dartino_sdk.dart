import 'dart:async';

import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';

import '../../atom.dart';
import 'sdk.dart';

class DartinoSdk extends Sdk {
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
}

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
