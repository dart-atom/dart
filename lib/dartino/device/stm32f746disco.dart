import 'dart:async';
import 'dart:convert';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';

import '../launch_dartino.dart';
import '../sdk/dartino_sdk.dart';
import 'device.dart';

/// An STM32 Discovery board
class Stm32f746Disco extends Device {
  //TODO(danrubel) generalize STM boards and hopefully connected devices in general

  /// Return a target device for the given launch or `null` if none.
  static Future<Stm32f746Disco> forLaunch(DartinoLaunch launch) async {
    //TODO(danrubel) move this into the command line utility
    //TODO(danrubel) add Windows support
    String ttyPath;
    String mediaPath;

    if (isMac || isLinux) {
      var stdout = await exec('ls', ['-1', '/dev']);
      if (stdout == null) return null;
      for (String line in LineSplitter.split(stdout)) {
        if (line.startsWith('tty.usb') || line.startsWith('ttyACM')) {
          ttyPath = '/dev/$line';
          break;
        }
      }
    }

    if (isMac) {
      mediaPath = '/Volumes/DIS_F746NG';
    }
    if (isLinux) {
      var stdout = await exec('df');
      if (stdout == null) return null;
      for (String line in LineSplitter.split(stdout)) {
        if (line.endsWith('/DIS_F746NG')) {
          mediaPath = line.substring(line.lastIndexOf(' /') + 1);
          break;
        }
      }
    }

    if (mediaPath == null || !fs.existsSync('$mediaPath/MBED.HTM')) return null;
    return new Stm32f746Disco(ttyPath, mediaPath);
  }

  final String ttyPath;
  final String mediaPath;

  Stm32f746Disco(this.ttyPath, this.mediaPath);

  @override
  Future<bool> launchDartino(DartinoSdk sdk, DartinoLaunch launch) async {
    //TODO(danrubel) add windows support and move this into cmdline util
    if (isWindows) {
      atom.notifications.addError('Platform not supported');
      return false;
    }
    // Deploy
    var exitCode = await launch.run(sdk.dartinoBinary,
        args: ['flash', launch.primaryResource],
        message: 'Compile and deploy to connected device ...');
    if (exitCode != 0) {
      atom.notifications.addError('Failed to deploy application',
          detail: 'Failed to deploy to device.\n'
              '${launch.primaryResource}\n'
              'to device. See console for more.');
      return false;
    }
    return true;
  }
}
