// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A Dart wrapper around the [Atom](https://atom.io/docs/api) apis.
library atom;

import 'dart:async';
import 'dart:html' hide File, Directory;
import 'dart:js';

import 'js.dart';
import 'utils.dart';

export 'js.dart' show Promise, ProxyHolder;

AtomPackage _package;

/// The singleton instance of [Atom].
final Atom atom = new Atom();

final JsObject _ctx = context['atom'];

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
  PackageManager _packages;
  Project _project;
  Workspace _workspace;

  Atom() : super(_ctx) {
    _commands = new CommandRegistry(obj['commands']);
    _config = new Config(obj['config']);
    _notifications = new NotificationManager(obj['notifications']);
    _packages = new PackageManager(obj['packages']);
    _project = new Project(obj['project']);
    _workspace = new Workspace(obj['workspace']);
  }

  CommandRegistry get commands => _commands;
  Config get config => _config;
  NotificationManager get notifications => _notifications;
  PackageManager get packages => _packages;
  Project get project => _project;
  Workspace get workspace => _workspace;

  void beep() => invoke('beep');
}

/// Represents the state of the user interface for the entire window. Interact
/// with this object to open files, be notified of current and future editors,
/// and manipulate panes. To add panels, you'll need to use the [WorkspaceView]
/// class for now until we establish APIs at the model layer.
class Workspace extends ProxyHolder {
  Workspace(JsObject object) : super(object);

  // TODO:

}

class CommandRegistry extends ProxyHolder {
  CommandRegistry(JsObject object) : super(object);

  void add(String target, String commandName, void callback(AtomEvent event)) {
    invoke('add', target, commandName, (e) => callback(new AtomEvent(e)));
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
  Disposable observe(String keyPath, Map options, void callback(value)) {
    if (options == null) options = {};
    return new JsDisposable(invoke('observe', keyPath, options, callback));
  }
}

class NotificationManager extends ProxyHolder {
  NotificationManager(JsObject object) : super(object);

  void addSuccess(String message, {Map options}) =>
      invoke('addSuccess', message, options);

  /// Show the given informational message. [options] can contain a `detail`
  /// message.
  void addInfo(String message, {Map options}) =>
      invoke('addInfo', message, options);

  void addWarning(String message, {Map options}) =>
      invoke('addWarning', message, options);

  void addError(String message, {Map options}) =>
      invoke('addError', message, options);

  void addFatalError(String message, {Map options}) =>
      invoke('addFatalError', message, options);
}

/// Package manager for coordinating the lifecycle of Atom packages. Packages
/// can be loaded, activated, and deactivated, and unloaded.
class PackageManager extends ProxyHolder {
  PackageManager(JsObject object) : super(object);

  /// Is the package with the given name bundled with Atom?
  bool isBundledPackage(name) => invoke('isBundledPackage', name);

  bool isPackageLoaded(String name) => invoke('isPackageLoaded', name);

  bool isPackageDisabled(String name) => invoke('isPackageDisabled', name);

  bool isPackageActive(String name) => invoke('isPackageActive', name);

  List<String> getAvailablePackageNames() => invoke('getAvailablePackageNames');
}

/// Represents a project that's opened in Atom.
class Project extends ProxyHolder {
  Project(JsObject object) : super(object);

  /// Fire an event when the project paths change. Each event is an list of
  /// project paths.
  Stream<List<String>> get onDidChangePaths => eventStream('onDidChangePaths');

  List<String> getPaths() => invoke('getPaths');

  List<Directory> getDirectories() {
    return invoke('getDirectories').map((dir) => new Directory(dir)).toList();
  }

  /// Get the path to the project directory that contains the given path, and
  /// the relative path from that project directory to the given path. Returns
  /// an array with two elements: `projectPath` - the string path to the project
  /// directory that contains the given path, or `null` if none is found.
  /// `relativePath` - the relative path from the project directory to the given
  /// path.
  List<String> relativizePath(String fullPath) =>
      invoke('relativizePath', fullPath);

  /// Determines whether the given path (real or symbolic) is inside the
  /// project's directory. This method does not actually check if the path
  /// exists, it just checks their locations relative to each other.
  bool contains(String pathToCheck) => invoke('contains', pathToCheck);
}

abstract class Entry extends ProxyHolder {
  Entry(JsObject object) : super(object);

  // TODO: onDidChange(callback)

  String get path => obj['path'];

  bool isFile() => invoke('isFile');
  bool isDirectory() => invoke('isDirectory');
  bool existsSync() => invoke('existsSync');

  String getBaseName() => invoke('getBaseName');
  String getPath() => invoke('getPath');
  String getRealPathSync() => invoke('getRealPathSync');

  Directory getParent() => new Directory(invoke('getParent'));

  String toString() => getPath();
}

class File extends Entry {
  File(JsObject object) : super(object);

  /// Get the SHA-1 digest of this file.
  String getDigestSync() => invoke('getDigestSync');

  String getEncoding() => invoke('getEncoding');

  /// Reads the contents of the file. [flushCache] indicates whether to require
  /// a direct read or if a cached copy is acceptable.
  Future<String> read([bool flushCache]) =>
      promiseToFuture(invoke('read', flushCache));

  /// Overwrites the file with the given text.
  void writeSync(String text) => invoke('writeSync', text);

  int get hashCode => getPath().hashCode;

  operator==(other) => other is File && getPath() == other.getPath();
}

class Directory extends Entry {
  Directory(JsObject object) : super(object);
  Directory.fromPath(String path) : super(_create('Directory', path));

  File getFile(filename) => new File(_cvt(invoke('getFile', filename)));
  Directory getSubdirectory(String dirname) =>
      new Directory(invoke('getSubdirectory', dirname));

  List<Entry> getEntriesSync() {
    return invoke('getEntriesSync').map((entry) {
      entry = _cvt(entry);
      return entry.callMethod('isFile') ? new File(entry) : new Directory(entry);
    }).toList();
  }

  int get hashCode => getPath().hashCode;

  operator==(other) => other is Directory && getPath() == other.getPath();
}

class AtomEvent extends ProxyHolder {
  AtomEvent(JsObject object) : super(object);

  void abortKeyBinding() => invoke('abortKeyBinding');
  void stopPropagation() => invoke('stopPropagation');
  void stopImmediatePropagation() => invoke('stopImmediatePropagation');
}

class BufferedProcess extends ProxyHolder {
  static BufferedProcess create(String command, {
      List<String> args,
      void stdout(String str),
      void stderr(String str),
      void exit(num code)
  }) {
    Map map = {'command': command};

    if (args != null) map['args'] = args;
    if (stdout != null) map['stdout'] = stdout;
    if (stderr != null) map['stderr'] = stderr;
    if (exit != null) map['exit'] = exit;

    JsObject ctor = require('atom')['BufferedProcess'];
    return new BufferedProcess._(new JsObject(ctor, [jsify(map)]));
  }

  BufferedProcess._(JsObject object) : super(object);

  void kill() => invoke('kill');
}

JsObject _create(String className, dynamic arg) {
  return new JsObject(require('atom')[className], [arg]);
}

JsObject _cvt(JsObject object) {
  if (object == null) return null;
  // TODO: We really shouldn't have to be wrapping objects we've already gotten
  // from JS interop.
  return new JsObject.fromBrowserObject(object);
}
