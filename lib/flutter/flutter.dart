import 'package:atom/atom.dart';
import 'package:atom_dartlang/sdk.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

final Logger _logger = new Logger('flutter');

final Flutter flutter = new Flutter();

class Flutter {
  static bool hasFlutterPlugin() {
    return atom.packages.getAvailablePackageNames().contains('flutter');
  }

  static void setMinSdkVersion() {
    if (hasFlutterPlugin()) {
      SdkManager.minVersion = new Version.parse('1.15.0');
    }
  }

  /// Called by the Flutter plugin to enable Flutter specific behavior.
  void enable([AtomEvent _]) {
    if (!hasFlutterPlugin()) return;
    _logger.info('Flutter features enabled');
  }
}
