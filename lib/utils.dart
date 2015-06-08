// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.utils;

import 'dart:async';

import 'atom.dart';
import 'js.dart';

/// 'darwin', 'freebsd', 'linux', 'sunos' or 'win32'
final String platform = require('process')['platform'];

final bool isWindows = platform.startsWith('win');
final bool isMac = platform == 'darwin';
final bool isLinux = !isWindows && !isMac;

final String separator = isWindows ? '\\' : '/';

final String loremIpsum = "Lorem ipsum dolor sit amet, consectetur adipiscing "
    "elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. "
    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi "
    "ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit"
    " in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur"
    " sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt "
    "mollit anim id est laborum.";

String join(dir, String arg1, [String arg2, String arg3]) {
  if (dir is Directory) dir = dir.path;
  String path = '${dir}${separator}${arg1}';
  if (arg2 != null) {
    path = '${path}${separator}${arg2}';
    if (arg3 != null) path = '${path}${separator}${arg3}';
  }
  return path;
}

String dirname(entry) {
  if (entry is Entry) return entry.getParent().path;
  int index = entry.lastIndexOf(separator);
  return index == -1 ? null : entry.substring(0, index);
}

abstract class Disposable {
  void dispose();
}

class Disposables implements Disposable {
  List<Disposable> _disposables = [];

  void add(Disposable disposable) {
    _disposables.add(disposable);
  }

  void dispose() {
    for (Disposable disposable in _disposables) {
      disposable.dispose();
    }

    _disposables.clear();
  }
}

class StreamSubscriptions {
  List<StreamSubscription> _subscriptions = [];

  void add(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }

  void cancel() {
    for (StreamSubscription subscription in _subscriptions) {
      subscription.cancel();
    }

    _subscriptions.clear();
  }
}
