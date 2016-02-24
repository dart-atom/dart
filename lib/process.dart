// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.process;

import 'dart:async';

import 'package:atom/node/process.dart';
import 'package:logging/logging.dart';

import 'atom.dart';

Logger _logger = new Logger("process");

/// A helper class to visualize a running process.
class ProcessNotifier {
  final String title;

  Notification _notification;
  NotificationHelper _helper;

  ProcessNotifier(this.title) {
    _notification = atom.notifications.addInfo(title,
        detail: '', description: 'Running…', dismissable: true);

    _helper = new NotificationHelper(_notification.view);
    _helper.setNoWrap();
    _helper.setRunning();
  }

  /// Visualize the running process; watch the stdout and stderr streams.
  /// Complete the returned future when the process completes. Note that errors
  /// from the process are not propagated through to the returned Future.
  Future<int> watch(ProcessRunner runner) {
    runner.onStdout.listen((str) => _helper.appendText(str));
    runner.onStderr.listen((str) => _helper.appendText(str, stderr: true));

    _notification.onDidDismiss.listen((_) {
      // If the process has not already exited, kill it.
      if (runner.exit == null) runner.kill();
    });

    return runner.onExit.then((int result) {
      if (result == 0) {
        _helper.showSuccess();
        _helper.setSummary('Finished.');
      } else {
        _helper.showError();
        _helper.setSummary('Finished with exit code ${result}.');
      }
      return result;
    });
  }
}
