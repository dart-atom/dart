
import '../launch/launch.dart';
import 'flutter_launch.dart';

class MojoLaunchType extends FlutterLaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new MojoLaunchType());

  MojoLaunchType() : super('mojo');

  String get flutterRunCommand => 'run_mojo';

  bool get supportsResident => false;

  // We don't want to advertise the mojo launch configuration as much as the
  // flutter one.
  bool canLaunch(String path, LaunchData data) => false;

  String getDefaultConfigText() {
    return 'checked: true\n# args:\n#  - --mojo-path=path/to/mojo';
  }
}
