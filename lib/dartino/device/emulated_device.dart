import 'dart:async';

import 'package:atom/atom.dart';

import '../launch_dartino.dart';
import '../sdk/dartino_sdk.dart';
import '../sdk/sdk.dart';
import 'device.dart';

/// An emulated device
class EmulatedDevice extends Device {
  /// Return a target device for the given launch or `null` if none.
  static Future<EmulatedDevice> forLaunch(Sdk sdk, DartinoLaunch launch) async {
    return new EmulatedDevice();
  }

  @override
  Future<bool> launchDartino(DartinoSdk sdk, DartinoLaunch launch) async {
    if (!await launch.debug(sdk, null)) {
      atom.notifications.addError('Failed to start debug session',
          detail: 'Failed to start debug session on emulated device.\n'
              '${launch.primaryResource}\n'
              'See console for more.');
      return false;
    }
    return true;
  }
}
