// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.smoketest;

import 'dart:async';

import '../atom.dart';

void smokeTest() {
  // files
  List<Directory> dirs = atom.project.getDirectories();
  print("project directories = ${dirs}");
  print("project.getPaths() = ${atom.project.getPaths()}");
  Directory dir = dirs.first;
  _printDir(dir);
  _printDir(dir.getParent());
  // TODO: getEntriesSync currently does not work.
  // List<Entry> children = dir.getEntriesSync();
  // File childFile = children.firstWhere((e) => e is File);
  // _printFile(childFile);
  // _printFile(dir.getFile(childFile.getBaseName()));
  // childFile.read().then((contents) => print('read file contents for ${childFile}'));
  // Directory childDir = children.firstWhere((e) => e is Directory);
  // _printDir(childDir);
  // _printDir(dir.getSubdirectory(childDir.getBaseName()));

  // futures
  new Future(() => print('futures work ctor'));
  new Future.microtask(() => print('futures work microtask'));
  new Future.delayed(new Duration(seconds: 1), () => print('futures work delayed'));

  // notifications
  atom.notifications.addSuccess('Hello world from dart-lang!');
  atom.notifications.addInfo(
    'Hello world from dart-lang!', options: {'detail': 'Foo bar.'});
  atom.notifications.addWarning('Hello world from dart-lang!');

  // processes
  BufferedProcess.create('date',
    stdout: (str) => print("stdout: ${str}"),
    stderr: (str) => print("stderr: ${str}"),
    exit: (code) => print('exit code = ${code}'));

  // TODO:
  // events
  // subscriptions.add(atom.project.onDidChangePaths.listen((e) {
  //   print("dirs = ${e}");
  // }));
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
