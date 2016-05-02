
import 'package:atom/atom.dart';

class Flutter {
  static bool hasFlutterPlugin() {
    return atom.packages.getAvailablePackageNames().contains('flutter');
  }
}
