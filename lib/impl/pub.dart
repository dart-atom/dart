// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.pub;

import 'dart:async';

import '../atom.dart';
import '../atom_utils.dart';
import '../jobs.dart';
import '../sdk.dart';
import '../state.dart';
import '../utils.dart';

const String pubspecFileName = 'pubspec.yaml';

class PubManager implements Disposable {
  Disposables disposables = new Disposables();

  PubManager() {
    // pub get
    _addSdkCmd('atom-text-editor', 'dartlang:pub-get', (event) {
      new PubJob.get(dirname(event.editor.getPath())).schedule();
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-get', (AtomEvent event) {
      new PubJob.get(dirname(event.selectedFilePath)).schedule();
    });

    // pub upgrade
    _addSdkCmd('atom-text-editor', 'dartlang:pub-upgrade', (event) {
      new PubJob.upgrade(dirname(event.editor.getPath())).schedule();
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-upgrade', (event) {
      new PubJob.upgrade(dirname(event.selectedFilePath)).schedule();
    });

    // pub run
    _addSdkCmd('atom-workspace', 'dartlang:pub-run', (event) {
      _handleRun(atom.workspace.getActiveTextEditor());
    });
    _addSdkCmd('atom-workspace', 'dartlang:pub-global-run', (event) {
      _handleGlobalRun(atom.workspace.getActiveTextEditor());
    });

    // activate
    _addSdkCmd('atom-workspace', 'dartlang:pub-global-activate', (event) {
      _handleGlobalActivate();
    });
  }

  // Validate that an sdk is available before calling the target function.
  void _addSdkCmd(String target, String command, void callback(AtomEvent e)) {
    disposables.add(atom.commands.add(target, command, (event) {
      if (!sdkManager.hasSdk) {
        sdkManager.showNoSdkMessage();
      } else {
        callback(event);
      }
    }));
  }

  void _handleRun(TextEditor editor) {
    if (editor == null) {
      atom.notifications
          .addWarning("This commands requires an open file editor.");
      return;
    }

    String path = editor.getPath();
    if (editor.getPath() == null) {
      atom.beep();
      return;
    }

    String dir = _locatePubspecDir(path);
    if (dir == null) {
      atom.notifications
          .addWarning("No pubspec.yaml file found for '${path}'.");
      return;
    }

    String lastRunText = state['lastRunText'];

    promptUser('pub run: pub application to run (ex. sky:init).',
        defaultText: lastRunText, selectText: true).then((String response) {
      if (response == null) return;
      response = response.trim();
      state['lastRunText'] = response;
      List<String> args = response.split(' ');
      new PubRunJob(dir, args).schedule();
    });
  }

  void _handleGlobalRun(TextEditor editor) {
    String path = editor == null ? null : editor.getPath();
    String dir = path == null ? null : _locatePubspecDir(path);
    String lastRunText = state['lastGlobalRunText'];

    promptUser('pub global run: pub application to run (ex. sky:init).',
        defaultText: lastRunText, selectText: true).then((String response) {
      if (response == null) return;
      response = response.trim();
      state['lastGlobalRunText'] = response;
      List<String> args = response.split(' ');
      new PubRunJob.global(dir, args).schedule();
    });
  }

  void _handleGlobalActivate() {
    promptUser('pub global activate: pub package to activate.').then((String response) {
      if (response == null) return;
      response = response.trim();
      new PubGlobalActivate(response).schedule();
    });
  }

  void dispose() => disposables.dispose();
}

class PubJob extends Job {
  final String path;
  final String pubCommand;

  String _pubspecDir;

  PubJob.get(this.path)
      : pubCommand = 'get',
        super('Pub get') {
    _pubspecDir = _locatePubspecDir(path);
  }

  PubJob.upgrade(this.path)
      : pubCommand = 'upgrade',
        super('Pub upgrade') {
    _pubspecDir = _locatePubspecDir(path);
  }

  bool get pinResult => true;

  Object get schedulingRule => _pubspecDir;

  Future run() {
    return sdkManager.sdk
        .execBinSimple('pub', [pubCommand], cwd: _pubspecDir)
        .then((ProcessResult result) {
      if (result.exit != 0) throw '${result.stdout}\n${result.stderr}';
      return result.stdout;
    });
  }
}

class PubRunJob extends Job {
  final String path;
  final List<String> args;
  final bool isGlobal;

  String _pubspecDir;

  PubRunJob(this.path, List<String> args)
      : this.args = args,
        isGlobal = false,
        super("Pub run '${args.first}'") {
    _pubspecDir = _locatePubspecDir(path);
  }

  PubRunJob.global(this.path, List<String> args)
      : args = args,
        isGlobal = true,
        super("Pub global run '${args.first}'") {
    _pubspecDir = _locatePubspecDir(path);
  }

  bool get pinResult => true;

  Object get schedulingRule => _pubspecDir;

  Future run() {
    List<String> l = isGlobal ? ['global', 'run'] : ['run'];
    l.addAll(args);
    return sdkManager.sdk
        .execBinSimple('pub', l, cwd: _pubspecDir)
        .then((ProcessResult result) {
      if (result.exit != 0) throw '${result.stdout}\n${result.stderr}';
      return result.stdout;
    });
  }
}

String _locatePubspecDir(String path) {
  if (path == null) return null;
  Directory dir = new Directory.fromPath(path);

  if (new File.fromPath(join(path, pubspecFileName)).existsSync()) {
    return dir.path;
  }

  while (!dir.isRoot() && dir.path.length > 2) {
    if (dir.getFile(pubspecFileName).existsSync()) {
      return dir.path;
    }
    dir = dir.getParent();
  }

  return null;
}

class PubGlobalActivate extends Job {
  final String packageName;

  PubGlobalActivate(String packageName) : this.packageName = packageName,
      super("Pub global activate '${packageName}'");

  bool get pinResult => true;

  Future run() {
    return sdkManager.sdk
        .execBinSimple('pub', ['global', 'activate', packageName])
        .then((ProcessResult result) {
      if (result.exit != 0) throw '${result.stdout}\n${result.stderr}';
      return result.stdout;
    });
  }
}
