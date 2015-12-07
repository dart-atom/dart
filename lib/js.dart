// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// JavaScript utility code.
library atom.js;

import 'dart:async';
import 'dart:convert';
import 'dart:js';

import 'package:logging/logging.dart';

import 'utils.dart';

export 'dart:js' show JsObject;

final JsObject _browserWindow = new JsObject.fromBrowserObject(context['window']);
final JsObject _browserJson = _browserWindow['JSON'];

Logger _logger = new Logger("js");

JsObject jsify(obj) {
  if (obj == null) return null;
  if (obj is JsObject) return obj;
  if (obj is List || obj is Map) return new JsObject.jsify(obj);
  if (obj is ProxyHolder) return obj.obj;
  return obj;
}

JsObject require(String input) => context.callMethod('require', [input]);

JsObject uncrackDart2js(dynamic obj) => context.callMethod('uncrackDart2js', [obj]);

/// Convert a JsObject to a List or Map based on `JSON.stringify` and
/// dart:convert's `JSON.decode`.
dynamic jsObjectToDart(JsObject obj) {
  if (obj == null) return null;

  try {
    String str = _browserJson.callMethod('stringify', [obj]);
    return JSON.decode(str);
  } catch (e, st) {
    _logger.severe('jsObjectToDart', e, st);
  }
}

dynamic dartObjectToJS(dynamic obj) {
  if (obj == null) return null;

  try {
    String str = JSON.encode(obj);
    return _browserJson.callMethod('parse', [str]);
  } catch (e, st) {
    _logger.severe('dartObjectToJS', e, st);
  }
}

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

    StreamController controller = new StreamController.broadcast(
        onCancel: () => disposable?.dispose());

    try {
      disposable = new JsDisposable(
        invoke(eventName, (evt) => controller.add(evt)));
    } catch (e, st) {
      _logger.warning('error listening to ${eventName}', e, st);
    }

    return controller.stream;
  }

  // TODO: This seems to be buggy.
  // Stream eventStream2Args(String eventName, arg1, arg2) {
  //   Disposable disposable;
  //   StreamController<List<String>> controller = new StreamController.broadcast(
  //       onCancel: () => disposable.dispose());
  //
  //   try {
  //     disposable = new JsDisposable(
  //       invoke(eventName, arg1, arg2, (evt) => controller.add(evt)));
  //   } catch (e, st) {
  //     _logger.warning('error listening to ${eventName}', e, st);
  //   }
  //
  //   return controller.stream;
  // }

  int get hashCode => obj.hashCode;

  bool operator==(other) => other is ProxyHolder && obj == other.obj;
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
        resolve.apply([jsify(result)]);
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

/// A utility class to wrap calling `addEventListener` and `removeEventListener`.
class EventListener implements Disposable {
  final JsObject obj;
  final String eventName;

  dynamic _callback;

  EventListener(this.obj, this.eventName, void fn(JsObject e)) {
    _callback = new JsFunction.withThis((_this, e) => fn(new JsObject.fromBrowserObject(e)));
    obj.callMethod('addEventListener', [eventName, _callback]);
  }

  void dispose() {
    if (_callback != null) {
      obj.callMethod('removeEventListener', [eventName, _callback]);
    }
    _callback = null;
  }
}
