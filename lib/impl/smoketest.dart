// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.smoketest;

import 'dart:async';
import 'dart:html' show DivElement;

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/process.dart';
import 'package:atom/node/workspace.dart';

import '../jobs.dart';
import '../launch/launch.dart';
import '../launch/launch_cli.dart';
import '../projects.dart';
import '../sdk.dart';
import '../state.dart';
import '../utils.dart';

void smokeTest() {
  // panels
  DivElement element = new DivElement()..text = "Hello world.";
  Panel panel = atom.workspace.addTopPanel(item: element, visible: true);
  panel.onDidDestroy.listen((p) => print('panel was destroyed'));

  // files
  List<Directory> dirs = atom.project.getDirectories();
  print("project directories = ${dirs}");
  print("project.getPaths() = ${atom.project.getPaths()}");
  Directory dir = dirs.first;
  _printDir(dir);
  _printDir(dir.getParent());
  List<Entry> children = dir.getEntriesSync();
  File childFile = children.firstWhere((e) => e is File);
  _printFile(childFile);
  _printFile(dir.getFile(childFile.getBaseName()));
  childFile.read().then((contents) => print('read ${childFile} contents'));
  Directory childDir = children.firstWhere((e) => e is Directory);
  _printDir(childDir);
  _printDir(dir.getSubdirectory(childDir.getBaseName()));

  // // resolve symlinks
  // String path = '/Users/test/homebrew/bin/dart';
  // File symDir = new File.fromPath(path);
  // print('getPath()         = ${symDir.getPath()}');
  // print('path              = ${symDir.path}');
  // print('getRealPathSync() = ${symDir.getRealPathSync()}');
  // print('realpathSync()    = ${realpathSync(path)}');
  // print('existsSync()      = ${symDir.existsSync()}');

  // futures
  new Future(() => print('futures work ctor'));
  new Future.microtask(() => print('futures work microtask'));
  new Future.delayed(new Duration(seconds: 2), () {
    print('futures delayed');
    panel.destroy();
  });

  // notifications
  Notification notification = atom.notifications.addInfo(
    'Hello world from dart-lang!',
    detail: 'Foo bar 1.',
    description: ' ',
    dismissable: true);
  notification.onDidDismiss.listen((_) => print('notification closed'));
  atom.notifications.addSuccess('Hello world from dart-lang!');
  atom.notifications.addWarning('Hello world from dart-lang!', detail: loremIpsum);
  NotificationHelper helper = new NotificationHelper(notification.view);
  helper.setSummary('Running…');
  helper.setNoWrap();
  helper.setRunning();
  helper.appendText('Foo bar 2.');
  new Timer(new Duration(seconds: 3), () {
    helper.appendText('Foo bar 3.');
    helper.setSummary('Finished in 3.10 seconds.');
    helper.showSuccess();
  });

  // processes
  BufferedProcess.create('pwd',
    stdout: (str) => print("stdout: ${str}"),
    stderr: (str) => print("stderr: ${str}"),
    exit: (code) => print('exit code: ${code}'));
  exec('date').then((str) => print('exec date: ${str}'));
  // BufferedProcess p = BufferedProcess.create('dart', args: ['foo.dart'],
  //   stdout: (str) => print("stdout: ${str}"),
  //   stderr: (str) => print("stderr: ${str}"),
  //   exit: (code) => print('exit code: ${code}'));
  // p.write('lorem\n');
  // p.write('ipsum\n');

  // launches
  Launch launch = new Launch(launchManager, new CliLaunchType(), null, 'launch_test.sh');
  launchManager.addLaunch(launch);
  new Timer(new Duration(seconds: 12), () => launch.launchTerminated(0));

  // sdk
  var sdk = sdkManager.sdk;
  print('dart sdk: ${sdk}');
  if (sdk != null) {
    print('sdk isValidSdk() = ${sdk.isValidSdk}');
    sdk.getVersion().then((ver) => print('sdk version ${ver}'));
    File vm = sdk.dartVm;
    print('vm is ${vm}, exists = ${vm.existsSync()}');
  }

  // sdk auto-discovery
  new SdkDiscovery().discoverSdk().then((String foundSdk) {
    print('discoverSdk: ${foundSdk}');
  });

  // dart projects
  List<DartProject> projects = projectManager.projects;
  print('${projects.length} dart projects');
  projects.forEach(print);

  // jobs
  new _TestJob("Lorem ipsum dolor", 1).schedule();
  new _TestJob("Sit amet consectetur", 2).schedule();
  new _TestJob("Adipiscing elit sed", 3, () {
    atom.notifications.addSuccess('Hello world from dart-lang!');
  }).schedule();
  new _TestJob("Do eiusmod tempor", 4).schedule();

  // utils
  print("platform: '${process.platform}'");
  print('isWindows: ${isWindows}');
  print('isMac: ${isMac}');
  print('isLinux: ${isLinux}');

  // Timer.periodic
  int timerCount = 0;
  new Timer.periodic(new Duration(seconds: 1), (Timer timer) {
    print('timer ${timerCount++}');
    if (timerCount >= 3) timer.cancel();
  });
}

class _TestJob extends Job {
  final int seconds;
  final VoidHandler _infoAction;
  _TestJob(String title, this.seconds, [this._infoAction]) : super(title, _TestJob);
  VoidHandler get infoAction => _infoAction;
  Future run() => new Future.delayed(new Duration(seconds: seconds));
}

void _printEntry(Entry entry) {
  print('${entry}:');
  print("  entry.isFile() = ${entry.isFile()}");
  print("  entry.isDirectory() = ${entry.isDirectory()}");
  print("  entry.existsSync() = ${entry.existsSync()}");
  print("  entry.getBaseName() = ${entry.getBaseName()}");
  print("  entry.getPath() = ${entry.getPath()}");
  print("  entry.getRealPathSync() = ${entry.getRealPathSync()}");
}

void _printFile(File file) {
  _printEntry(file);
  print("  file.getDigestSync() = ${file.getDigestSync()}");
  print("  file.getEncoding() = ${file.getEncoding()}");
}

void _printDir(Directory dir) {
  _printEntry(dir);
}
