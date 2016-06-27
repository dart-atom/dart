import 'dart:async';
import 'dart:convert';

import 'package:atom/atom.dart';
import 'package:atom/node/process.dart';

import '../launch_dartino.dart';
import '../sdk/dartino_sdk.dart';
import '../sdk/sdk.dart';
import 'device.dart';

/// An Dartuino board
class DartuinoBoard extends Device {
  /// Return a target device for the given launch or `null` if none.
  static Future<DartuinoBoard> forLaunch(Sdk sdk, DartinoLaunch launch) async {
    //TODO(danrubel) add Windows support

    if (isMac || isLinux) {
      String ttyPath;
      // Old style interaction with device via TTY
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
      if (ttyPath != null) return new DartuinoBoard(ttyPath);
    }
    return null;
  }

  final String ttyPath;

  DartuinoBoard(this.ttyPath);

  @override
  Future<bool> launchDartino(DartinoSdk sdk, DartinoLaunch launch) async {
    atom.notifications.addError('Dartino not yet supported on this board');
    return false;
  }
}
