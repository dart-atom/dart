library atom.web_launch;

import 'dart:async';

import '../launch.dart';
import '../projects.dart';

class WebLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new WebLaunchType());

  WebLaunchType() : super('web');

  bool canLaunch(String path) => path.endsWith('.html');

  List<String> getLaunchablesFor(DartProject project) {
    // TODO: Do not traverse lib, build, dot folders, symlinks, 'packages' folders

    return [];
  }

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    // TODO:

    return new Future.error(new UnimplementedError());
  }
}
