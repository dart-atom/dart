import 'dart:async';

import 'package:atom_dartlang/atom.dart';

import '../dartino_util.dart';
import '../launch_dartino.dart';
import '../sdk/dartino_sdk.dart';
import 'stm32f746disco.dart';

/// The connected device on which the application is executed.
abstract class Device {
  /// Return a target device for the given launch.
  /// If there is a problem or a compatible device cannot be found
  /// then notify the user and return `null`.
  static Future<Device> forLaunch(DartinoLaunch launch) async {
    Device device = await Stm32f746Disco.forLaunch(launch);
    if (device == null) {
      if (dartino.devicePath.isEmpty) {
        atom.notifications.addError('No connected devices found.',
            detail: 'Please connect the device and try again.\n'
                ' \n'
                'If the device is already connected, '
                'please set the device path in\n'
                'Settings > Packages > dartino > Device Path',
            buttons: [
              new NotificationButton('Open settings', dartino.openSettings)
            ]);
      } else {
        atom.notifications.addError('Device not found',
            detail: 'Could not find specified device:\n'
                '${dartino.devicePath}\n'
                ' \n'
                'Please connect the device and try again\n'
                'or change/remove the device path in\n'
                'Settings > Packages > dartino > Device Path',
            buttons: [
              new NotificationButton('Open settings', dartino.openSettings)
            ]);
      }
    }
    return device;
  }

  /// Launch the specified application [binPath] on the device and return `true`.
  /// If there is a problem, notify the user and return `false`.
  Future<bool> launchDartino(DartinoSdk sdk, DartinoLaunch launch);
}
