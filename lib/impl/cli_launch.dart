library atom.cli_launch;

import 'dart:async';

import '../launch.dart';

class CliLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new CliLaunchType());

  CliLaunchType() : super('cli');

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    return new Future.error(new UnimplementedError());
  }
}
