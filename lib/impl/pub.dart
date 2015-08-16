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

class PubManager implements Disposable, ContextMenuContributor {
  Disposables disposables = new Disposables();

  PubManager() {
    // get, update, run
    _addSdkCmd('atom-text-editor', 'dartlang:pub-get', (event) {
      new PubJob.get(dirname(event.editor.getPath())).schedule();
    });
    _addSdkCmd('atom-text-editor', 'dartlang:pub-upgrade', (event) {
      new PubJob.upgrade(dirname(event.editor.getPath())).schedule();
    });
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

    // TODO: expose pub run...
    _addSdkCmd('.tree-view', 'dartlang:pub-get', (AtomEvent event) {
      new PubJob.get(event.targetFilePath).schedule();
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-upgrade', (AtomEvent event) {
      new PubJob.upgrade(event.targetFilePath).schedule();
    });
  }

  List<ContextMenuItem> getTreeViewContributions() {
    return [
      new PubContextCommand('Pub Get', 'dartlang:pub-get'),
      new PubContextCommand('Pub Upgrade', 'dartlang:pub-upgrade')
    ];
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
      new PubRunJob.local(dir, args).schedule();
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
      new PubRunJob.global(args, path: dir).schedule();
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

/// A Dart app installed via pub.
class PubApp {
  final String name;
  final bool isGlobal;

  bool _installed;

  PubApp.global(this.name) : isGlobal = true;

  Future<bool> isInstalled() {
    if (isGlobal) {
      if (_installed != null) return new Future.value(_installed);

      return sdkManager.sdk.execBinSimple('pub', ['global', 'list']).then(
          (ProcessResult result) {
        if (result.exit != 0) throw '${result.stdout}\n${result.stderr}';
        List lines = result.stdout.trim().split('\n');
        return lines.any((l) => l.startsWith('${name} '));
      }).then((installed) {
        _installed = installed;
        return _installed;
      });
    } else {
      return new Future.value(true);
    }
  }

  Future install({bool verbose: true}) {
    if (isGlobal) {
      Job job = new PubGlobalActivate(name);
      return job.schedule();
    } else {
      return new Future.value();
    }
  }

  Future run({List<String> args, String cwd, bool verbose: true}) {
    List list = [name];
    if (args != null) list.addAll(args);
    Job job = new PubRunJob.global(list, path: cwd, verbose: verbose);
    return job.schedule();
  }
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
  final bool verbose;

  String _pubspecDir;

  PubRunJob.local(this.path, List<String> args, {this.verbose: true})
      : this.args = args,
        isGlobal = false,
        super("Pub run '${args.first}'") {
    _pubspecDir = _locatePubspecDir(path);
  }

  PubRunJob.global(List<String> args, {this.path, this.verbose: true})
      : args = args,
        isGlobal = true,
        super("Pub global run '${args.first}'") {
    _pubspecDir = _locatePubspecDir(path);
  }

  bool get pinResult => verbose;

  Object get schedulingRule => _pubspecDir;

  Future run() {
    List<String> l = isGlobal ? ['global', 'run'] : ['run'];
    l.addAll(args);
    return sdkManager.sdk
        .execBinSimple('pub', l, cwd: _pubspecDir)
        .then((ProcessResult result) {
      if (result.exit != 0) throw '${result.stdout}\n${result.stderr}';
      return verbose ? result.stdout : null;
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

class PubContextCommand extends ContextMenuItem {
  PubContextCommand(String label, String command) : super(label, command);

  bool shouldDisplay(AtomEvent event) {
    String filePath = event.targetFilePath;
    if (filePath == null) return false;
    if (basename(filePath) == pubspecFileName) return true;
    File file = new File.fromPath(join(filePath, pubspecFileName));
    return file.existsSync();
  }
}
