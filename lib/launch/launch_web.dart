library atom.launch_web;

import 'dart:async';

import 'launch.dart';

class WebLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new WebLaunchType());

  WebLaunchType() : super('web');

  bool canLaunch(String path, LaunchData data) => path.endsWith('.html');

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    // TODO:
    return new Future.error(new UnimplementedError());
  }

  String getDefaultConfigText() => null;
}
