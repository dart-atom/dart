// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.sdk;

import 'dart:async';

import 'atom.dart';
import 'process.dart';
import 'utils.dart';

export 'process.dart' show ProcessResult;

final String _sdkPrefPath = 'dart-lang.sdkLocation';

class SdkManager implements Disposable {
  StreamController<Sdk> _controller = new StreamController.broadcast(sync: true);

  Sdk _sdk;
  Disposable _locationObserve;

  SdkManager() {
    _locationObserve = atom.config.observe(_sdkPrefPath, null, (value) {
      _setTo(value == null ? null : new Directory.fromPath(value));
    });
  }

  bool get hasSdk => _sdk != null;

  Sdk get sdk => _sdk;

  void showNoSdkMessage() {
    atom.notifications.addInfo(
        'No Dart SDK found.',
        detail: 'You can configure your SDK location in Settings > Packages > dart-lang > Settings.',
        dismissable: true);
  }

  // TODO: Also provide a debounced sdk change stream (observe sdk?).

  Stream<Sdk> get onSdkChange => _controller.stream;

  void _setTo(Directory dir) {
    if (!dir.existsSync()) dir = null;

    if (dir == null) {
      if (_sdk != null) {
        _sdk = null;
        _controller.add(null);
      }
    } else if (_sdk == null || dir != _sdk.directory) {
      _sdk = new Sdk(dir);
      _controller.add(_sdk);
    }
  }

  void dispose() {
    _locationObserve.dispose();
  }
}

class Sdk {
  final Directory directory;

  Sdk(this.directory);

  bool get isValidSdk => directory.getFile('version').existsSync();

  Future<String> getVersion() {
    File f = directory.getFile('version');
    return f.read().then((data) => data.trim());
  }

  // TODO: process finagling on the mac; exec in the bash shell

  /// Execute the given SDK binary (a command in the `bin/` folder). [cwd] can
  /// be either a [String] or a [Directory].
  Future<ProcessResult> execBinSimple(String binName, List<String> args, {cwd}) {
    if (cwd is Directory) cwd = cwd.path;
    String command = join(directory, 'bin', isWindows ? '${binName}.bat' : binName);
    return new ProcessRunner(command, args: args, cwd: cwd).execSimple();
  }

  String toString() => directory.getPath();
}
