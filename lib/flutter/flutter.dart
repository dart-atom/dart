import 'package:atom/atom.dart';
import 'package:atom_dartlang/sdk.dart';
import 'package:pub_semver/pub_semver.dart';

class Flutter {
  static bool hasFlutterPlugin() {
    return atom.packages.getAvailablePackageNames().contains('flutter');
  }

  static void setMinSdkVersion() {
    if (hasFlutterPlugin()) {
      SdkManager.minVersion = new Version.parse('1.15.0');
    }
  }
}
