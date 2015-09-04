// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.pub;

import 'dart:async';

import '../atom.dart';
import '../atom_utils.dart';
import '../jobs.dart';
import '../process.dart' show ProcessNotifier, ProcessRunner;
import '../projects.dart';
import '../sdk.dart';
import '../state.dart';
import '../utils.dart';

const String pubspecFileName = 'pubspec.yaml';
const String dotPackagesFileName = '.packages';

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
    _addSdkCmd('atom-text-editor', 'dartlang:pub-run', (event) {
      _handleRun(editor: atom.workspace.getActiveTextEditor());
    });
    _addSdkCmd('atom-text-editor', 'dartlang:pub-global-run', (event) {
      _handleGlobalRun(editor: atom.workspace.getActiveTextEditor());
    });

    // activate
    _addSdkCmd('atom-workspace', 'dartlang:pub-global-activate', (event) {
      _handleGlobalActivate();
    });

    _addSdkCmd('.tree-view', 'dartlang:pub-get', (AtomEvent event) {
      new PubJob.get(event.targetFilePath).schedule();
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-upgrade', (AtomEvent event) {
      new PubJob.upgrade(event.targetFilePath).schedule();
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-run', (AtomEvent event) {
      _handleRun(path: event.targetFilePath);
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-global-run', (AtomEvent event) {
      _handleGlobalRun(path: event.targetFilePath);
    });
  }

  List<ContextMenuItem> getTreeViewContributions() {
    return [
      new PubContextCommand('Pub Get', 'dartlang:pub-get', true),
      new PubContextCommand('Pub Upgrade', 'dartlang:pub-upgrade', true),
      new PubContextCommand('Pub Run…', 'dartlang:pub-run', false),
      new PubContextCommand('Pub Global Run…', 'dartlang:pub-global-run', false)
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

  void _handleRun({TextEditor editor, String path}) {
    if (editor != null) path = editor.getPath();

    if (editor == null && path == null) {
      atom.notifications.addWarning("This command requires an open file editor.");
      return;
    }

    if (path == null) {
      atom.beep();
      return;
    }

    String dir = _locatePubspecDir(path);
    if (dir == null) {
      atom.notifications.addWarning("No pubspec.yaml file found for '${path}'.");
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

  void _handleGlobalRun({TextEditor editor, String path}) {
    if (editor != null) path = editor.getPath();
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

  Future run({List<String> args, String cwd}) {
    List list = [name];
    if (args != null) list.addAll(args);
    Job job = new PubRunJob.global(list, path: cwd);
    return job.schedule();
  }
}

class PubJob extends Job {
  static bool get _noPackageSymlinks =>
      atom.config.getValue('${pluginId}.noPackageSymlinks');

  final String path;
  final String pubCommand;

  String _pubspecDir;

  PubJob.get(this.path) : pubCommand = 'get', super('Pub get') {
    _pubspecDir = _locatePubspecDir(path);
  }

  PubJob.upgrade(this.path) : pubCommand = 'upgrade', super('Pub upgrade') {
    _pubspecDir = _locatePubspecDir(path);
  }

  bool get quiet => true;

  Object get schedulingRule => _pubspecDir;

  Future run() {
    List<String> args = [pubCommand];
    if (_noPackageSymlinks) args.insert(0, '--no-package-symlinks');

    ProcessNotifier notifier = new ProcessNotifier(name);
    ProcessRunner runner = sdkManager.sdk.execBin('pub', args, cwd: _pubspecDir);
    return notifier.watch(runner);
  }
}

class PubRunJob extends Job {
  final String path;
  final List<String> args;
  final bool isGlobal;

  String _pubspecDir;

  PubRunJob.local(this.path, List<String> args)
      : this.args = args,
        isGlobal = false,
        super("Pub run '${args.first}'") {
    _pubspecDir = _locatePubspecDir(path);
  }

  PubRunJob.global(List<String> args, {this.path})
      : args = args,
        isGlobal = true,
        super("Pub global run '${args.first}'") {
    _pubspecDir = _locatePubspecDir(path);
  }

  bool get quiet => true;

  Object get schedulingRule => _pubspecDir;

  Future run() {
    List<String> l = isGlobal ? ['global', 'run'] : ['run'];
    l.addAll(args);
    ProcessNotifier notifier = new ProcessNotifier(name);
    ProcessRunner runner = sdkManager.sdk.execBin('pub', l, cwd: _pubspecDir);
    return notifier.watch(runner);
  }
}

String _locatePubspecDir(String path) {
  if (path == null) return null;
  DartProject project = projectManager.getProjectFor(path);
  return project == null ? null : project.path;
}

class PubGlobalActivate extends Job {
  final String packageName;

  PubGlobalActivate(String packageName) : this.packageName = packageName,
      super("Pub global activate '${packageName}'");

  bool get quiet => true;

  Future run() {
    ProcessNotifier notifier = new ProcessNotifier(name);
    ProcessRunner runner = sdkManager.sdk.execBin('pub', ['global', 'activate', packageName]);
    return notifier.watch(runner);
  }
}

class PubContextCommand extends ContextMenuItem {
  final bool onlyPubspec;

  PubContextCommand(String label, String command, this.onlyPubspec) :
      super(label, command);

  bool shouldDisplay(AtomEvent event) {
    String filePath = event.targetFilePath;
    if (filePath == null) return false;
    DartProject project = projectManager.getProjectFor(filePath);
    if (project == null) return null;

    if (onlyPubspec) {
      File file = new File.fromPath(join(project.path, pubspecFileName));
      return file.existsSync();
    } else {
      return true;
    }
  }
}
