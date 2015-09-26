library atom.web_launch;

import 'dart:async';

import '../launch.dart';

class WebLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new WebLaunchType());

  WebLaunchType() : super('web');

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    return new Future.error(new UnimplementedError());
  }
}
