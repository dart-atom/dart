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

  StreamController<String> _stdoutController = new StreamController.broadcast();
  StreamController<String> _stderrController = new StreamController.broadcast();

  ProcessRunner(this.command, {this.args, this.cwd, this.env});

  bool get started => _process != null;
  bool get finished => _exit != null;

  int get exit => _exit;

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
          _exit = code;
          _exitCompleter.complete(code);
        });

    return _exitCompleter.future;
  }

  void write(String str) => _process.write(str);

  Future<int> kill() {
    _process.kill();
    return _exitCompleter.future;
  }
}

class ProcessResult {
  final int exit;
  final String stdout;
  final String stderr;

  ProcessResult(this.exit, this.stdout, this.stderr);

  String toString() => '${exit}';
}
