// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.projects;

import 'atom.dart';
import 'utils.dart';

class ProjectManager implements Disposable {
  ProjectManager();

  void dispose() {
    // TODO:
  }
}

class DartProject {
  final Directory directory;

  DartProject(this.directory);

  String get path => directory.path;

  int get hashCode => directory.hashCode;
  operator==(other) => other is DartProject && directory == other.directory;
  String toString() => '[Project ${directory.getBaseName()}]';
}
