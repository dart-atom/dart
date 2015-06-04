// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A Dart wrapper around the [Atom](https://atom.io/docs/api) apis.
library atom;

import 'dart:html';
import 'dart:js';

import 'js.dart';

export 'js.dart' show ProxyHolder;

AtomPackage _package;

/// The singleton instance of [Atom].
final Atom atom = new Atom();

/// An Atom package. Register your package using [registerPackage].
abstract class AtomPackage {
  Map config() => {};

  void packageActivated([Map state]) { }

  void packageDeactivated() { }

  Map serialize() => {};
}

/**
 * Call this method once from the main method of your package.
 *
 *     main() => registerPackage(new MyFooPackage());
 */
void registerPackage(AtomPackage package) {
  if (_package != null) {
    throw new StateError('can only register one package');
  }

  _package = package;

  final JsObject exports = context['module']['exports'];

  exports['activate'] = _package.packageActivated;
  exports['deactivate'] = _package.packageDeactivated;
  exports['config'] = jsify(_package.config());
  exports['serialize'] = _package.serialize;
}

class Atom extends ProxyHolder {
  CommandRegistry _commands;
  Config _config;
  NotificationManager _notifications;

  Atom() : super(context['atom']) {
    _commands = new CommandRegistry(obj['commands']);
    _config = new Config(obj['config']);
    _notifications = new NotificationManager(obj['notifications']);
  }

  CommandRegistry get commands => _commands;
  Config get config => _config;
  NotificationManager get notifications => _notifications;

  void beep() => invoke('beep');
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

class Config extends ProxyHolder {
  Config(JsObject object) : super(object);

  /// [keyPath] should be in the form `pluginid.keyid` - e.g.
  /// `dart-lang.sdkLocation`.
  dynamic get(String keyPath) => invoke('get', keyPath);

  void set(String keyPath, dynamic value) => invoke('set', keyPath, value);

  /// Add a listener for changes to a given key path. This will immediately call
  /// your callback with the current value of the config entry.
  void observe(String keyPath, Map options, void callback(value)) {
    if (options == null) options = {};
    invoke('observe', keyPath, options, callback);
  }
}

class NotificationManager extends ProxyHolder {
  NotificationManager(JsObject object) : super(object);

  /// Show the given informational message. [options] can contain a `detail`
  /// message.
  void addInfo(String message, {Map options}) =>
      invoke('addInfo', message, options);
}

class AtomEvent extends ProxyHolder {
  AtomEvent(JsObject object) : super(object);

  void stopPropagation() => invoke('stopPropagation');
  void stopImmediatePropagation() => invoke('stopImmediatePropagation');
}
