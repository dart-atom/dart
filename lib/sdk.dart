// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.sdk;

import 'dart:async';

import 'atom.dart';
import 'utils.dart';

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

  Sdk get sdk => _sdk;

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
    return f.read().then((data) {
      return data.trim();
    });
  }

  String toString() => directory.getPath();
}
