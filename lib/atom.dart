// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A Dart wrapper around the [Atom](https://atom.io/docs/api) apis.
library atom;

import 'dart:html';
import 'dart:js';

final Atom atom = new Atom();

AtomPackage _package;

abstract class AtomPackage {
  void packageActivated([Map state]) { }

  void packageDeactivated() { }

  Map serialize() => {};
}

void registerPackage(AtomPackage package) {
  if (_package != null) {
    throw new StateError('can only register one package');
  }

  _package = package;

  final JsObject exports = context['module']['exports'];

  exports['activate'] = _package.packageActivated;
  exports['deactivate'] = _package.packageDeactivated;
  exports['serialize'] = _package.serialize;
}

class Atom extends ProxyHolder {
  CommandRegistry _commands;
  NotificationManager _notifications;

  Atom() : super(context['atom']) {
    _commands = new CommandRegistry(obj['commands']);
    _notifications = new NotificationManager(obj['notifications']);
  }

  NotificationManager get notifications => _notifications;

  CommandRegistry get commands => _commands;

  void beep() => invoke('beep');
}

class NotificationManager extends ProxyHolder {
  NotificationManager(JsObject object) : super(object);

  /// Show the given informational message. [options] can contain a `detail`
  /// message.
  void addInfo(String message, {Map options}) =>
      invoke('addInfo', message, options);
}

class CommandRegistry extends ProxyHolder {
  CommandRegistry(JsObject object) : super(object);

  void add(String target, String commandName, void callback(AtomEvent event)) {
    invoke('add', target, commandName, (e) {
      callback(new AtomEvent(e));
    });
  }

  void dispatch(Element target, String commandName) =>
      invoke('dispatch', target, commandName);
}

class AtomEvent extends ProxyHolder {
  AtomEvent(JsObject object) : super(object);

  void stopPropagation() => invoke('stopPropagation');  
  void stopImmediatePropagation() => invoke('stopImmediatePropagation');
}

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
}

JsObject jsify(Map map) => new JsObject.jsify(map);
