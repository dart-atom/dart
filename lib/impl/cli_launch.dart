library atom.cli_launch;

import '../launch.dart';

class CliLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new CliLaunchType());
      
  CliLaunchType() : super('cli');
}
