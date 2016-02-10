library atom.flutter.mojo_launch;

import '../launch/launch.dart';
import 'flutter_launch.dart';

class MojoLaunchType extends FlutterLaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new MojoLaunchType());

  MojoLaunchType() : super();

  String get type => 'mojo';

  String get flutterStartCommand => 'run_mojo';

  String getDefaultConfigText() {
    return 'checked: true\n# args:\n#  - --mojo-path=path/to/mojo';
  }
}
