import 'dart:async';
import 'dart:convert';

import 'package:atom/atom.dart';
import 'package:atom/node/process.dart';

import '../launch_dartino.dart';
import '../sdk/dartino_sdk.dart';
import '../sdk/sod_repo.dart';
import 'device.dart';

/// An Dartuino board
class DartuinoBoard extends Device {
  /// Return a target device for the given launch or `null` if none.
  static Future<DartuinoBoard> forLaunch(DartinoLaunch launch) async {
    //TODO(danrubel) move this into the command line utility
    //TODO(danrubel) add Windows support
    String ttyPath;

    if (isMac || isLinux) {
      var stdout = await exec('ls', ['-1', '/dev']);
      if (stdout == null) return null;
      for (String line in LineSplitter.split(stdout)) {
        // TODO(danrubel) move this out of dartlang into the dartino
        // and SOD command line utilities - dartino show usb devices
        if (line.startsWith('tty.usb') || line.startsWith('ttyUSB')) {
          ttyPath = '/dev/$line';
          // This board surfaces 2 tty ports... and only the 2nd one works
          // so continue looping to pick up the 2nd tty port
        }
      }
    }

    if (ttyPath == null) return null;
    return new DartuinoBoard(ttyPath);
  }

  final String ttyPath;

  DartuinoBoard(this.ttyPath);

  @override
  Future<bool> launchDartino(DartinoSdk sdk, DartinoLaunch launch) async {
    atom.notifications.addError('Dartino not yet supported on this board');
    return false;
  }

  @override
  Future<bool> launchSOD(SodRepo sdk, DartinoLaunch launch) async {
    //TODO(danrubel) add windows and mac support and move this into cmdline util
    if (isWindows && isMac) {
      atom.notifications.addError('Platform not supported');
      return false;
    }
    // Compile
    String binPath = await sdk.compile(launch);
    if (binPath == null) return false;
    // Deploy and run
    var exitCode = await launch.run('dart',
        args: [sdk.sodUtil, 'run', binPath, 'on', ttyPath],
        message: 'Deploy and run on connected device ...');
    if (exitCode != 0) {
      atom.notifications.addError('Failed to deploy application',
          detail: 'Failed to deploy to device.\n'
              '${launch.primaryResource}\n'
              'See console for more.');
      return false;
    }
    return true;
  }
}
