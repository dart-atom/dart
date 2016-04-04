// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A Dart wrapper around the [Atom](https://atom.io/docs/api) apis.

import 'dart:async';
import 'dart:html' hide File, Notification, Point;
import 'dart:js';

import 'package:atom/node/config.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/node.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/src/js.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

export 'package:atom/src/js.dart' show Promise, ProxyHolder;

final Logger _logger = new Logger('atom');

final JsObject _fs = require('fs');
final JsObject _os = require('os');
final JsObject _shell = require('shell');

/// The singleton instance of [Atom].
final Atom atom = new Atom();

final JsObject _ctx = context['atom'];

class Atom extends ProxyHolder {
  CommandRegistry _commands;
  Config _config;
  ContextMenuManager _contextMenu;
  GrammarRegistry _grammars;
  NotificationManager _notifications;
  PackageManager _packages;
  Project _project;
  ViewRegistry _views;
  Workspace _workspace;

  Atom() : super(_ctx) {
    _commands = new CommandRegistry(obj['commands']);
    _config = new Config(obj['config']);
    _contextMenu = new ContextMenuManager(obj['contextMenu']);
    _grammars = new GrammarRegistry(obj['grammars']);
    _notifications = new NotificationManager(obj['notifications']);
    _packages = new PackageManager(obj['packages']);
    _project = new Project(obj['project']);
    _views = new ViewRegistry(obj['views']);
    _workspace = new Workspace(obj['workspace']);
  }

  CommandRegistry get commands => _commands;
  Config get config => _config;
  ContextMenuManager get contextMenu => _contextMenu;
  GrammarRegistry get grammars => _grammars;
  NotificationManager get notifications => _notifications;
  PackageManager get packages => _packages;
  Project get project => _project;
  ViewRegistry get views => _views;
  Workspace get workspace => _workspace;

  String getVersion() => invoke('getVersion');

  void beep() => invoke('beep');

  /// A flexible way to open a dialog akin to an alert dialog.
  ///
  /// Returns the chosen button index Number if the buttons option was an array.
  int confirm(String message, {String detailedMessage, List<String> buttons}) {
    Map m = {'message': message};
    if (detailedMessage != null) m['detailedMessage'] = detailedMessage;
    if (buttons != null) m['buttons'] = buttons;
    return invoke('confirm', m);
  }

  /// Reload the current window.
  void reload() => invoke('reload');

  /// Prompt the user to select one or more folders.
  Future<String> pickFolder() {
    Completer<String> completer = new Completer();
    invoke('pickFolder', (result) {
      if (result is List && result.isNotEmpty) {
        completer.complete(result.first);
      } else {
        completer.complete(null);
      }
    });
    return completer.future;
  }
}

class CommandRegistry extends ProxyHolder {
  StreamController<String> _dispatchedController = new StreamController.broadcast();

  CommandRegistry(JsObject object) : super(object);

  Stream<String> get onDidDispatch => _dispatchedController.stream;

  /// Add one or more command listeners associated with a selector.
  ///
  /// [target] can be a String - a css selector - or an Html Element.
  Disposable add(dynamic target, String commandName, void callback(AtomEvent event)) {
    return new JsDisposable(invoke('add', target, commandName, (e) {
      _dispatchedController.add(commandName);
      callback(new AtomEvent(e));
    }));
  }

  /// Simulate the dispatch of a command on a DOM node.
  void dispatch(Element target, String commandName, {Map options}) =>
      invoke('dispatch', target, commandName, options);
}

/// Provides a registry for commands that you'd like to appear in the context
/// menu.
class ContextMenuManager extends ProxyHolder {
  ContextMenuManager(JsObject obj) : super(obj);

  /// Add context menu items scoped by CSS selectors.
  Disposable add(String selector, List<ContextMenuItem> items) {
    Map m = {selector: items.map((item) => item.toJs()).toList()};
    return new JsDisposable(invoke('add', m));
  }
}

abstract class ContextMenuItem {
  static final ContextMenuItem separator = new _SeparatorMenuItem();

  final String label;
  final String command;

  ContextMenuItem(this.label, this.command);

  bool shouldDisplay(AtomEvent event);

  JsObject toJs() {
    Map m = {
      'label': label,
      'command': command,
      'shouldDisplay': (e) => shouldDisplay(new AtomEvent(e))
    };
    return jsify(m);
  }
}

abstract class ContextMenuContributor {
  List<ContextMenuItem> getTreeViewContributions();
}

class _SeparatorMenuItem extends ContextMenuItem {
  _SeparatorMenuItem() : super('', '');
  bool shouldDisplay(AtomEvent event) => true;
  JsObject toJs() => jsify({'type': 'separator'});
}

/// Package manager for coordinating the lifecycle of Atom packages. Packages
/// can be loaded, activated, and deactivated, and unloaded.
class PackageManager extends ProxyHolder {
  PackageManager(JsObject object) : super(object);

  /// Get the path to the apm command.
  ///
  /// Return a String file path to apm.
  String getApmPath() => invoke('getApmPath');

  /// Get the paths being used to look for packages.
  List<String> getPackageDirPaths() => new List.from(invoke('getPackageDirPaths'));

  /// Is the package with the given name bundled with Atom?
  bool isBundledPackage(name) => invoke('isBundledPackage', name);

  bool isPackageLoaded(String name) => invoke('isPackageLoaded', name);

  bool isPackageDisabled(String name) => invoke('isPackageDisabled', name);

  bool isPackageActive(String name) => invoke('isPackageActive', name);

  List<String> getAvailablePackageNames() =>
      new List.from(invoke('getAvailablePackageNames'));

  /// Activate a single package by name.
  Future activatePackage(String name) {
    return promiseToFuture(invoke('activatePackage', name));
  }
}

/// Represents a project that's opened in Atom.
class Project extends ProxyHolder {
  Project(JsObject object) : super(object);

  /// Fire an event when the project paths change. Each event is an list of
  /// project paths.
  Stream<List<String>> get onDidChangePaths => eventStream('onDidChangePaths')
      as Stream<List<String>>;

  List<String> getPaths() => new List.from(invoke('getPaths'));

  List<Directory> getDirectories() {
    return new List.from(invoke('getDirectories').map((dir) => new Directory(dir)));
  }

  /// Add a path to the project's list of root paths.
  void addPath(String path) => invoke('addPath', path);

  /// Remove a path from the project's list of root paths.
  void removePath(String path) => invoke('removePath', path);

  /// Get the path to the project directory that contains the given path, and
  /// the relative path from that project directory to the given path. Returns
  /// an array with two elements: `projectPath` - the string path to the project
  /// directory that contains the given path, or `null` if none is found.
  /// `relativePath` - the relative path from the project directory to the given
  /// path.
  List<String> relativizePath(String fullPath) =>
      new List.from(invoke('relativizePath', fullPath));

  /// Determines whether the given path (real or symbolic) is inside the
  /// project's directory. This method does not actually check if the path
  /// exists, it just checks their locations relative to each other.
  bool contains(String pathToCheck) => invoke('contains', pathToCheck);
}

class AtomEvent extends ProxyHolder {
  AtomEvent(JsObject object) : super(_cvt(object));

  dynamic get currentTarget => obj['currentTarget'];

  /// Return the editor that is the target of this event. Note, this is _only_
  /// available if an editor is the target of an event; calling this otherwise
  /// will return an invalid [TextEditor].
  TextEditor get editor {
    TextEditorElement view = new TextEditorElement(currentTarget);
    return view.getModel();
  }

  // /// Return the currently selected file item. This call will only be meaningful
  // /// if the event target is the Tree View.
  // Element get selectedFileItem {
  //   Element element = currentTarget;
  //   return element.querySelector('li[is=tree-view-file].selected span.name');
  // }
  //
  // /// Return the currently selected file path. This call will only be meaningful
  // /// if the event target is the Tree View.
  // String get selectedFilePath {
  //   Element element = selectedFileItem;
  //   return element == null ? null : element.getAttribute('data-path');
  // }

  /// Return the currently selected file path. This call will only be meaningful
  /// if the event target is the Tree View.
  String get targetFilePath {
    try {
      var target = obj['target'];

      // Target is an Element or a JsObject. JS interop is a mess.
      if (target is Element) {
        if (target.getAttribute('data-path') != null) {
          return target.getAttribute('data-path');
        }
        if (target.children.isEmpty) return null;
        Element child = target.children.first;
        return child.getAttribute('data-path');
      } else if (target is JsObject) {
        JsObject obj = target.callMethod('querySelector', ['span']);
        if (obj == null) return null;
        obj = new JsObject.fromBrowserObject(obj);
        return obj.callMethod('getAttribute', ['data-path']);
      } else {
        return null;
      }
    } catch (e, st) {
      _logger.info('exception while handling context menu', e, st);
      return null;
    }
  }

  void abortKeyBinding() => invoke('abortKeyBinding');

  bool get keyBindingAborted => obj['keyBindingAborted'];

  void preventDefault() => invoke('preventDefault');

  bool get defaultPrevented => obj['defaultPrevented'];

  void stopPropagation() => invoke('stopPropagation');
  void stopImmediatePropagation() => invoke('stopImmediatePropagation');

  bool get propagationStopped => obj['propagationStopped'];
}

JsObject _cvt(JsObject object) {
  if (object == null) return null;
  // We really shouldn't have to be wrapping objects we've already gotten from
  // JS interop.
  return new JsObject.fromBrowserObject(object);
}
