library atom.shell_launch;

import '../launch.dart';

class ShellLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new ShellLaunchType());

  ShellLaunchType() : super('shell');
}
