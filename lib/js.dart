// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// JavaScript utility code.
library atom.js;

import 'dart:async';
import 'dart:js';

import 'utils.dart';

JsObject jsify(obj) {
  if (obj == null) return null;
  if (obj is JsObject) return obj;
  if (obj is List || obj is Map) return new JsObject.jsify(obj);
  if (obj is ProxyHolder) return obj.obj;
  return obj;
}

JsObject require(String input) => context.callMethod('require', [input]);

Future promiseToFuture(promise) {
  if (promise is JsObject) promise = new Promise(promise);
  Completer completer = new Completer();
  promise.then((result) {
    completer.complete(result);
  }, (error) {
    completer.completeError(error);
  });
  return completer.future;
}

class ProxyHolder {
  final JsObject obj;

  ProxyHolder(this.obj);

  dynamic invoke(String method, [dynamic arg1, dynamic arg2, dynamic arg3]) {
    if (arg1 != null) arg1 = jsify(arg1);
    if (arg2 != null) arg2 = jsify(arg2);
    if (arg3 != null) arg3 = jsify(arg3);

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

  Stream eventStream(String eventName) {
    Disposable disposable;
    StreamController<List<String>> controller = new StreamController.broadcast(
        onCancel: () => disposable.dispose());
    disposable = new JsDisposable(
        invoke(eventName, (evt) => controller.add(evt)));
    return controller.stream;
  }
}

class Promise<T> extends ProxyHolder {
  static _jsObjectFromFuture(Future future) {
    // var promise = new Promise(function(resolve, reject) {
    //   // do a thing, possibly async, then…
    //
    //   if (/* everything turned out fine */) {
    //     resolve("Stuff worked!");
    //   } else {
    //     reject(Error("It broke"));
    //   }
    // });

    var callback = (resolve, reject) {
      future.then((result) {
        resolve.apply([result]);
      }).catchError((e) {
        reject.apply([e]);
      });
    };

    return new JsObject(context['Promise'], [callback]);
  }

  Promise(JsObject object) : super(object);
  Promise.fromFuture(Future future) : super(_jsObjectFromFuture(future));

  void then(void thenCallback(T response), [void errorCallback(e)]) {
    invoke("then", thenCallback, errorCallback);
  }

  void error(void errorCallback(e)) => invoke("catch", errorCallback);
}

class JsDisposable extends ProxyHolder implements Disposable {
  JsDisposable(JsObject object) : super(object);

  void dispose() => invoke('dispose');
}
