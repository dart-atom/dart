import 'dart:async';

import 'package:atom/atom.dart';

import '../launch_dartino.dart';
import '../sdk/dartino_sdk.dart';
import '../sdk/sdk.dart';
import 'device.dart';

/// A device for running a Dartino app on the local host/developer machine.
class LocalDevice extends Device {
  /// Return a target device for the given launch or `null` if none.
  static Future<LocalDevice> forLaunch(Sdk sdk, DartinoLaunch launch) async {
    return new LocalDevice();
  }

  @override
  Future<bool> launchDartino(DartinoSdk sdk, DartinoLaunch launch) async {
    if (!await launch.debug(sdk, null)) {
      atom.notifications.addError('Failed to start debug session',
          detail: 'Failed to start debug session on local machine.\n'
              '${launch.primaryResource}\n'
              'See console for more.');
      return false;
    }
    return true;
  }
}
