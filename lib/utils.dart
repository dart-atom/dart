// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.utils;

import 'dart:async';

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

class Streams {
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
