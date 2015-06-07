// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Wrapper over the analysis server providing a simplified API and automatic
/// handling of reliability.
library atom.analysis_server;

import 'dart:async' as async;

class AnalysisServer {
  String _sdkPath;

  AnalysisServer(this._sdkPath);

  void _setup() {
    // Init server and warmup
    // Setup watchdog
  }

  /// Provides an instantaneous snapshot of the known issues and warnings.
  List<AnalysisIssue> get issues => null;
  /// Subscribe to this to get told when the issues list has changed.
  async.Stream get issuesUpdatedNotification => null;


  /// Compute completions for a given location.
  List<Completion> computeCompletions(String sourcePath, int offset) => null;


  /// Tell the analysis server a file has changed in memory.
  void notifyFileChanged(String path, String contents) => null;
  /// Tell the analysis server a file should be included in analysis.
  void watchFiles(List<String> path) => null;
  /// Tell the analysis server a file should not be included in analysis.
  void unwatchFiles(List<String> path) => null;


  /// Force recycle of the analysis server.
  void forceReset() => null;

}

class AnalysisIssue {}
class Completion {}