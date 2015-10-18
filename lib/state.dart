// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.state;

import 'dart:async';

import 'analysis_server.dart';
import 'debug/breakpoints.dart';
import 'debug/debugger.dart';
import 'dependencies.dart';
import 'editors.dart';
import 'error_repository.dart';
import 'jobs.dart';
import 'launch/launch.dart';
import 'projects.dart';
import 'sdk.dart';

export 'dependencies.dart' show deps;

final String pluginId = 'dartlang';

AnalysisServer get analysisServer => deps[AnalysisServer];
EditorManager get editorManager => deps[EditorManager];
ErrorRepository get errorRepository => deps[ErrorRepository];
JobManager get jobs => deps[JobManager];
LaunchManager get launchManager => deps[LaunchManager];
DebugManager get debugManager => deps[DebugManager];
BreakpointManager get breakpointManager => deps[BreakpointManager];
ProjectManager get projectManager => deps[ProjectManager];
SdkManager get sdkManager => deps[SdkManager];
final State state = new State();

class State {
  Map _map = {};
  Map<String, StreamController> _controllers = {};

  State();

  dynamic operator[](String key) => _map[key];

  void operator[]=(String key, dynamic value) {
    _map[key] = value;

    if (_controllers[key] != null) _controllers[key].add(value);
  }

  void loadFrom(Map map) {
    if (map == null) map = {};
    _map = map;
  }

  Stream onValueChanged(String key) {
    if (_controllers[key] != null) {
      return _controllers[key].stream;
    } else {
      StreamController controller = new StreamController.broadcast(
        sync: true,
        onCancel: () => _controllers.remove(key));
      _controllers[key] = controller;
      return controller.stream;
    }
  }

  Map toMap() => _map;
}
