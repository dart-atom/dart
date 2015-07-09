// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.state;

import 'analysis_server.dart';
import 'dependencies.dart';
import 'editors.dart';
import 'error_repository.dart';
import 'jobs.dart';
import 'projects.dart';
import 'sdk.dart';

final String pluginId = 'dartlang';

AnalysisServer get analysisServer => deps[AnalysisServer];
EditorManager get editorManager => deps[EditorManager];
ErrorRepository get errorRepository => deps[ErrorRepository];
final JobManager jobs = new JobManager();
ProjectManager get projectManager => deps[ProjectManager];
SdkManager get sdkManager => deps[SdkManager];
