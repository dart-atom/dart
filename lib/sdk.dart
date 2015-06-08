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

    // Initiate auto-discovery.
    String sdkPrefValue = atom.config.get(_sdkPrefPath);
    if (sdkPrefValue == null || sdkPrefValue.isEmpty) {
      tryToAutoConfigure(complainOnFailure: false);
    }
  }

  bool get hasSdk => _sdk != null;

  Sdk get sdk => _sdk;

  void showNoSdkMessage() {
    atom.notifications.addInfo(
        'No Dart SDK found.',
        detail: 'You can configure your SDK location in Settings > Packages > dart-lang > Settings.',
        dismissable: true);
  }

  void tryToAutoConfigure({bool complainOnFailure: true}) {
    new SdkDiscovery().discoverSdk().then((String sdkPath) {
      if (sdkPath != null) {
        atom.notifications.addSuccess('Dart SDK found at ${sdkPath}.');
        atom.config.set(_sdkPrefPath, sdkPath);
      } else {
        if (complainOnFailure) {
          atom.notifications.addWarning('Unable to auto-locate a Dart SDK.');
        }
      }
    });
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

  bool get isValidSdk => directory.getSubdirectory('bin').existsSync();

  // Future<String> getVersion() {
  //   File f = directory.getFile('version');
  //   return f.read().then((data) => data.trim());
  // }

  // TODO: Process finagling on the mac; exec in the bash shell.

  /// Execute the given SDK binary (a command in the `bin/` folder). [cwd] can
  /// be either a [String] or a [Directory].
  Future<ProcessResult> execBinSimple(String binName, List<String> args, {cwd}) {
    if (cwd is Directory) cwd = cwd.path;
    String command = join(directory, 'bin', isWindows ? '${binName}.bat' : binName);
    return new ProcessRunner(command, args: args, cwd: cwd).execSimple();
  }

  String toString() => directory.getPath();
}

class SdkDiscovery {
  /// Try and auto-discover an SDK based on platform specific heuristics. This
  /// will return `null` if no SDK is found.
  Future<String> discoverSdk() {
    if (isMac) {
      // /bin/bash -c "which dart", /bin/bash -c "echo $PATH"
      return exec('/bin/bash', ['-l', '-c', 'which dart']).then((result) {
        return _resolveSdkFromVm(result);
      }).catchError((e) {
        return null;
      });
    } else if (isWindows) {
      // TODO: Also use the PATH var?
      return exec('where', ['dart.exe']).then((result) {
        if (result != null && !result.isEmpty) {
          if (result.contains('\n')) result = result.split('\n').first.trim();
          return _resolveSdkFromVm(result);
        }
      }).catchError((e) {
        return null;
      });
    } else {
      return exec('which', ['dart']).then((String result) {
        return _resolveSdkFromVm(result);
      }).catchError((e) {
        return null;
      });
    }
  }

  String _resolveSdkFromVm(String path) {
    if (path == null) return path;
    // TODO: resolve symlinks
    //String resolvedPath = require('fs').callMethod('realpathSync', [path]);
    File file = new File.fromPath(path);
    Directory binDir = file.getParent();
    return binDir.getParent().getPath();
  }
}
