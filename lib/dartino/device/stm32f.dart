import 'dart:async';
import 'dart:convert';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';

import '../launch_dartino.dart';
import '../sdk/dartino_sdk.dart';
import '../sdk/sdk.dart';
import 'device.dart';

/// An STM32F Discovery or Nucleo board
class Stm32f extends Device {
  //TODO(danrubel) generalize STM boards and hopefully connected devices in general

  /// Return a target device for the given launch or `null` if none.
  static Future<Stm32f> forLaunch(Sdk sdk, DartinoLaunch launch) async {
    //TODO(danrubel) move this into the command line utility
    //TODO(danrubel) add Windows support
    String ttyPath;
    String mediaPath;

    if (isMac || isLinux) {
      var stdout = await exec('ls', ['-1', '/dev']);
      if (stdout == null) return null;
      for (String line in LineSplitter.split(stdout)) {
        // TODO(danrubel) move this out of dartlang into the dartino
        // and SOD command line utilities - dartino show usb devices
        if (line.startsWith('tty.usb') || line.startsWith('ttyACM')) {
          ttyPath = '/dev/$line';
          break;
        }
      }
    }

    for (String mediaName in <String>[
      'DIS_F746NG', // STM32F746 Discovery
      'NODE_F411RE', // STM32F411 Nucleo
    ]) {
      if (isMac) {
        mediaPath = '/Volumes/$mediaName';
      }
      if (isLinux) {
        var stdout = await exec('df');
        if (stdout == null) return null;
        for (String line in LineSplitter.split(stdout)) {
          if (line.endsWith('/$mediaName')) {
            mediaPath = line.substring(line.lastIndexOf(' /') + 1);
            break;
          }
        }
      }

      if (mediaPath != null ||
          !fs.existsSync('$mediaPath/MBED.HTM') ||
          !fs.existsSync('$mediaPath/mbed.htm')) {
        return new Stm32f(ttyPath, mediaPath);
      }
    }
    return null;
  }

  final String ttyPath;
  final String mediaPath;

  Stm32f(this.ttyPath, this.mediaPath);

  @override
  Future<bool> launchDartino(DartinoSdk sdk, DartinoLaunch launch) async {
    //TODO(danrubel) add windows support and move this into cmdline util
    if (isWindows) {
      atom.notifications.addError('Platform not supported');
      return false;
    }

    // TODO(danrubel) use the code below
    // rather than `launch.launchConfiguration.debug`
    // because we want `debug` to default `false`
    // until this new feature is ready.
    var debug = launch.launchConfiguration.typeArgs['debug'];
    if (debug is! bool) debug = false;

    // Compile, deploy, and run
    var args = ['flash', launch.primaryResource];
    if (debug) args.insert(1, '--debugging-mode');
    var exitCode = await launch.run(sdk.dartinoBinary,
        args: args,
        message: 'Compile and deploy to connected device ...',
        isLast: !debug);
    if (exitCode != 0) {
      atom.notifications.addError('Failed to deploy application',
          detail: 'Failed to deploy to device.\n'
              '${launch.primaryResource}\n'
              'See console for more.');
      launch.launchTerminated(1, quiet: true);
      return false;
    }

    // If debugging then connect and start a debug session
    if (debug && !await launch.debug(sdk, ttyPath)) {
      atom.notifications.addError('Failed to start debug session',
          detail: 'Failed to start debug session on device.\n'
              '${launch.primaryResource}\n'
              'See console for more.');
      return false;
    }
    return true;
  }
}
