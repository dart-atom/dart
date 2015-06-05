// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// JavaScript utility code.
library atom.js;

import 'dart:js';

JsObject jsify(Map map) => new JsObject.jsify(map);

JsObject require(String input) => context.callMethod('require', [input]);

class ProxyHolder {
  final JsObject obj;

  ProxyHolder(this.obj);

  dynamic invoke(String method, [dynamic arg1, dynamic arg2, dynamic arg3]) {
    if (arg1 is Map) arg1 = jsify(arg1);
    if (arg2 is Map) arg2 = jsify(arg2);
    if (arg3 is Map) arg3 = jsify(arg3);

    if (arg3 != null) {
      return obj.callMethod(method, [arg1, arg2, arg3]);
    } else if (arg2 != null) {
      return obj.callMethod(method, [arg1, arg2]);
    } else if (arg1 != null) {
      return obj.callMethod(method, [arg1]);
    } else {
      return obj.callMethod(method);
    }
  }

  Disposable eventDisposable(String eventName, void callback(data)) {
    return new Disposable(invoke(eventName, callback));
  }
}

class Promise<T> extends ProxyHolder {
  Promise(JsObject object) : super(object);

  void then(void thenCallback(T response), [void errorCallback(e)]) {
    invoke("then", thenCallback, errorCallback);
  }

  void error(void errorCallback(e)) => invoke("catch", errorCallback);
}

class Disposable extends ProxyHolder {
  Disposable(JsObject object) : super(object);

  void dispose() => invoke('dispose');
}

class Disposables {
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
