// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.process;

import 'dart:async';

import 'package:logging/logging.dart';

import 'atom.dart';

Logger _logger = new Logger("process");

Future<String> exec(String cmd, [List<String> args]) {
  ProcessRunner runner = new ProcessRunner(cmd, args: args);
  return runner.execSimple().then((ProcessResult result) {
    if (result.exit == 0) {
      return result.stdout;
    } else {
      throw result.exit;
    }
  });
}

class ProcessRunner {
  final String command;
  final List<String> args;
  final String cwd;
  final Map<String, String> env;

  BufferedProcess _process;
  Completer<int> _exitCompleter = new Completer();
  int _exit;

  StreamController<String> _stdoutController = new StreamController();
  StreamController<String> _stderrController = new StreamController();

  ProcessRunner(this.command, {this.args, this.cwd, this.env});

  bool get started => _process != null;
  bool get finished => _exit != null;

  int get exit => _exit;

  Future<int> get onExit => _exitCompleter.future;

  Stream<String> get onStdout => _stdoutController.stream;
  Stream<String> get onStderr => _stderrController.stream;

  Future<ProcessResult> execSimple() {
    if (_process != null) throw new StateError('exec can only be called once');

    StringBuffer stdout = new StringBuffer();
    StringBuffer stderr = new StringBuffer();

    onStdout.listen((str) => stdout.write(str));
    onStderr.listen((str) => stderr.write(str));

    return execStreaming().then((code) {
      return new ProcessResult(code, stdout.toString(), stderr.toString());
    });
  }

  Future<int> execStreaming() {
    if (_process != null) throw new StateError('exec can only be called once');

    _logger.fine('exec: ${command} ${args == null ? "" : args.join(" ")}'
        '${cwd == null ? "" : " (cwd=${cwd})"}');

    _process = BufferedProcess.create(command, args: args, cwd: cwd, env: env,
        stdout: (s) => _stdoutController.add(s),
        stderr: (s) => _stderrController.add(s),
        exit: (code) {
          _logger.fine('exit code: ${code} (${command})');
          _exit = code;
          if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
        }
    );

    return _exitCompleter.future;
  }

  void write(String str) => _process.write(str);

  Future<int> kill() {
    _logger.fine('kill: ${command} ');
    _process.kill();
    new Future.delayed(new Duration(milliseconds: 50), () {
      if (!_exitCompleter.isCompleted) _exitCompleter.complete(0);
    });
    return _exitCompleter.future;
  }

  String getDescription() {
    if (args != null) {
      return '${command} ${args.join(' ')}';
    } else {
      return command;
    }
  }
}

class ProcessResult {
  final int exit;
  final String stdout;
  final String stderr;

  ProcessResult(this.exit, this.stdout, this.stderr);

  String toString() => '${exit}';
}

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
