// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.pub;

import 'dart:async';
import 'dart:convert' show JSON;
import 'dart:html' show HttpRequest;

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/process.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../jobs.dart';
import '../projects.dart';
import '../state.dart';

const String pubspecFileName = 'pubspec.yaml';
const String pubspecLockFileName = 'pubspec.lock';
const String dotPackagesFileName = '.packages';

final Logger _logger = new Logger('atom.pub');

class PubManager implements Disposable, ContextMenuContributor {
  Disposables disposables = new Disposables();

  PubManager() {
    // get, update, run
    _addSdkCmd('atom-text-editor', 'dartlang:pub-get', (event) {
      atom.workspace.saveAll();
      new PubJob.get(fs.dirname(event.editor.getPath())).schedule();
    });
    _addSdkCmd('atom-text-editor', 'dartlang:pub-upgrade', (event) {
      atom.workspace.saveAll();
      new PubJob.upgrade(fs.dirname(event.editor.getPath())).schedule();
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
      atom.workspace.saveAll();
      new PubJob.get(event.targetFilePath).schedule();
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-upgrade', (AtomEvent event) {
      atom.workspace.saveAll();
      new PubJob.upgrade(event.targetFilePath).schedule();
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-run', (AtomEvent event) {
      _handleRun(path: event.targetFilePath);
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-global-run', (AtomEvent event) {
      _handleGlobalRun(path: event.targetFilePath);
    });

    projectManager.projects.forEach(_handleProjectAdded);
    projectManager.onProjectAdd.listen(_handleProjectAdded);
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

    promptUser('pub run - pub application to run:',
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

    promptUser('pub global run - pub application to run:',
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

  void _handleProjectAdded(DartProject project) => _validatePubspecCurrent(project);

  // TODO: Remove pubspec.lock checking when the SDK revs.
  void _validatePubspecCurrent(DartProject project) {
    File pubspecYamlFile = project.directory.getFile(pubspecFileName);
    File pubspecLockFile = project.directory.getFile(pubspecLockFileName);
    File dotPackagesFile = project.directory.getFile(dotPackagesFileName);

    if (!pubspecYamlFile.existsSync()) return;

    // Prefer checking for a .packages file.
    if (dotPackagesFile.existsSync()) {
      var pubspecTime = fs.statSync(pubspecYamlFile.path).mtime;
      var packagesTime = fs.statSync(dotPackagesFile.path).mtime;
      bool dirty = pubspecTime.compareTo(packagesTime) > 0;
      if (dirty) _showRunPubDialog(project);
    } else if (pubspecLockFile.existsSync()) {
      var pubspecTime = fs.statSync(pubspecYamlFile.path).mtime;
      var lockTime = fs.statSync(pubspecLockFile.path).mtime;
      bool dirty = pubspecTime.compareTo(lockTime) > 0;
      if (dirty) _showRunPubDialog(project);
    } else {
      _showRunPubDialog(project, neverRun: true);
    }
  }

  void dispose() => disposables.dispose();

  void _showRunPubDialog(DartProject project, {bool neverRun: false}) {
    String title =
      "Pub has never been run for project `${project.workspaceRelativeName}`. "
      "Run 'pub get'?";

    if (!neverRun) {
      title =
        "The pubspec.yaml file for project `${project.workspaceRelativeName}` "
        "has been modified since pub was last run. Run 'pub get'?";
    }

    Notification _notification;
    _notification = atom.notifications.addInfo(
      title,
      dismissable: true,
      buttons: [
        new NotificationButton('Run pub get…', () {
          _notification.dismiss();
          new PubJob.get(project.path).schedule();
        })
      ]
    );
  }
}

/// A Dart app installed via pub.
abstract class PubApp {
  final String name;

  PubApp._(this.name);

  factory PubApp.local(String name, String cwd) {
    return new PubAppLocal(name, cwd);
  }

  factory PubApp.global(String name) {
    return new PubAppGlobal(name);
  }

  bool get isLocal;
  bool get isGlobal;

  Future run({List<String> args, String cwd, String title});

  Future<bool> isInstalled();

  Future<Version> getInstalledVersion();

  Future<Version> getMostRecentHostedVersion() {
    // https://pub.dartlang.org/packages/flutter.json
    // {"name":"flutter","versions":["0.0.6","0.0.5","0.0.4"]}

    return HttpRequest.request('https://pub.dartlang.org/packages/${name}.json').then(
        (HttpRequest result) {
      Map packageInfo = JSON.decode(result.responseText);
      Iterable<String> vers = packageInfo['versions'] as Iterable<String>;
      return Version.primary(vers.map((str) => new Version.parse(str)).toList());
    });
  }
}

class PubAppGlobal extends PubApp {
  PubAppGlobal(String name) : super._(name);

  bool get isLocal => false;
  bool get isGlobal => true;

  Future<bool> isInstalled() {
    return getInstalledVersion()
      .then((ver) => ver != null)
      .catchError((e) => false);
  }

  Future<Version> getInstalledVersion() {
    if (!sdkManager.hasSdk) return new Future.value();

    return sdkManager.sdk.execBinSimple('pub', ['global', 'list']).then(
        (ProcessResult result) {
      if (result.exit != 0) throw '${result.stdout}\n${result.stderr}';

      List<String> lines = result.stdout.trim().split('\n');

      for (String line in lines) {
        if (line.startsWith('${name} ')) {
          List<String> strs = line.split(' ');
          if (strs.length > 1) {
            try { return new Version.parse(strs[1]); }
            catch (_) { }
          }
        }
      }

      return null;
    });
  }

  Future install({bool quiet: true}) {
    if (!sdkManager.hasSdk) return new Future.value();
    Job job = new PubGlobalActivate(name, runQuiet: quiet);
    return job.schedule();
  }

  /// If this package is not installed, then install. If it is installed but the
  /// hosted version is newer, then re-install. Otherwise, this method does not
  /// re-install the package.
  Future installIfUpdateAvailable({bool quiet: true}) async {
    Version installedVer;

    try {
      installedVer = await getInstalledVersion();
    } catch (e) {
      return install();
    }

    _logger.fine('installed version for ${name} is ${installedVer}');

    if (installedVer == null || installedVer == Version.none) {
      return install();
    }

    // Check hosted version.
    return getMostRecentHostedVersion().then((Version hostedVer) {
      _logger.fine('hosted version for ${name} is ${hostedVer}');

      if (hostedVer != null && hostedVer > installedVer) {
        install();
      }
    }).catchError((e) {
      _logger.warning('Error getting the latest package version', e);
    });
  }

  Future run({List<String> args, String cwd, String title}) {
    if (!sdkManager.hasSdk) return new Future.error('no sdk installed');

    List<String> list = [name];
    if (args != null) list.addAll(args);
    Job job = new PubRunJob.global(list, path: cwd, title: title);
    return job.schedule();
  }
}

class PubAppLocal extends PubApp {
  final String cwd;

  PubAppLocal(String name, this.cwd) : super._(name);

  bool get isLocal => true;
  bool get isGlobal => false;

  Future<bool> isInstalled() => new Future.value(isInstalledSync());

  /// Returns whether this pub app is installed.
  bool isInstalledSync() {
    File packagesFile = new File.fromPath(fs.join(cwd, dotPackagesFileName));
    if (!packagesFile.existsSync()) return false;
    String contents = packagesFile.readSync();
    return contents.split('\n').any((String line) => line.startsWith('${name}:'));
  }

  Future<Version> getInstalledVersion() {
    // TODO:
    return new Future.error('todo');
  }

  /// Note: `PubAppLocal.run()` ignores the cwd parameter, and takes its cwd
  /// from the object constructor.
  Future run({List<String> args, String cwd, String title}) {
    if (!sdkManager.hasSdk) return new Future.error('no sdk installed');

    List<String> list = [name];
    if (args != null) list.addAll(args);
    Job job = new PubRunJob.local(this.cwd, list, title: title);
    return job.schedule();
  }

  ProcessRunner runRaw(List<String> args, {bool startProcess: true}) {
    List<String> _args = ['run', name];
    if (args != null) _args.addAll(args);
    return sdkManager.sdk.execBin('pub', _args, cwd: cwd, startProcess: startProcess);
  }
}

class PubJob extends Job {
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
    if (!sdkManager.hasSdk) {
      sdkManager.showNoSdkMessage();
      return new Future.value();
    }

    List<String> args = [pubCommand];
    ProcessNotifier notifier = new ProcessNotifier(name);
    ProcessRunner runner = sdkManager.sdk.execBin('pub', args, cwd: _pubspecDir);
    return notifier.watch(runner);
  }
}

class PubRunJob extends Job {
  final String path;
  final String title;
  final List<String> args;
  final bool isGlobal;

  String _pubspecDir;

  PubRunJob.local(this.path, List<String> args, {this.title})
      : this.args = args,
        isGlobal = false,
        super("Pub run '${args.first}'") {
    _pubspecDir = _locatePubspecDir(path);
  }

  PubRunJob.global(List<String> args, {this.path, this.title})
      : args = args,
        isGlobal = true,
        super("Pub global run '${args.first}'") {
    _pubspecDir = _locatePubspecDir(path);
  }

  bool get quiet => true;

  Object get schedulingRule => _pubspecDir;

  Future run() {
    if (!sdkManager.hasSdk) {
      sdkManager.showNoSdkMessage();
      return new Future.value();
    }

    List<String> l = isGlobal ? ['global', 'run'] : ['run'];
    l.addAll(args);
    ProcessNotifier notifier = new ProcessNotifier(title == null ? name : title);
    ProcessRunner runner = sdkManager.sdk.execBin('pub', l, cwd: _pubspecDir);
    return notifier.watch(runner);
  }
}

String _locatePubspecDir(String path) {
  if (path == null) return null;
  if (path.endsWith(pubspecFileName)) return fs.dirname(path);

  File f = new File.fromPath(fs.join(path, pubspecFileName));
  if (f.existsSync()) return path;

  DartProject project = projectManager.getProjectFor(path);
  return project == null ? null : project.path;
}

class PubGlobalActivate extends Job {
  final String packageName;
  final bool runQuiet;

  PubGlobalActivate(String packageName, {this.runQuiet: false}) :
      this.packageName = packageName, super("Pub global activate '${packageName}'");

  bool get quiet => runQuiet;

  Future run() {
    if (!sdkManager.hasSdk) {
      sdkManager.showNoSdkMessage();
      return new Future.value();
    }

    ProcessRunner runner = sdkManager.sdk.execBin(
        'pub', ['global', 'activate', packageName]);

    if (runQuiet) {
      // Run as a Job; display an error on failures.
      StringBuffer buf = new StringBuffer();

      runner.onStdout.listen((str) => buf.write(str));
      runner.onStderr.listen((str) => buf.write(str));

      return runner.onExit.then((int result) {
        if (result != 0) {
          buf.write('\nFinished with exit code ${result}.');
          throw buf.toString();
        }
      });
    } else {
      return new ProcessNotifier(name).watch(runner);
    }
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
      File file = new File.fromPath(fs.join(project.path, pubspecFileName));
      return file.existsSync();
    } else {
      return true;
    }
  }
}
