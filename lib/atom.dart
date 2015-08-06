// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A Dart wrapper around the [Atom](https://atom.io/docs/api) apis.
library atom;

import 'dart:async';
import 'dart:html' hide File, Directory, Point;
import 'dart:js';

import 'package:logging/logging.dart';

import 'js.dart';
import 'utils.dart';

export 'js.dart' show Promise, ProxyHolder;

final Logger _logger = new Logger('atom');

AtomPackage _package;

/// The singleton instance of [Atom].
final Atom atom = new Atom();

final Shell shell = new Shell();

final JsObject _ctx = context['atom'];

/// An Atom package. Register your package using [registerPackage].
abstract class AtomPackage {
  Map<String, Function> _registeredMethods = {};

  AtomPackage();

  Map config() => {};
  void packageActivated([Map state]) { }
  void packageDeactivated() { }
  Map serialize() => {};

  /// Register a method for a service callback (`consumedServices`).
  void registerServiceConsumer(String methodName, Disposable callback(JsObject obj)) {
    if (_registeredMethods == null) {
      throw new StateError('method must be registered in the package ctor');
    }
    _registeredMethods[methodName] = callback;
    return null;
  }

  void registerServiceProvider(String methodName, JsObject callback()) {
    if (_registeredMethods == null) {
      throw new StateError('method must be registered in the package ctor');
    }
    _registeredMethods[methodName] = callback;
    return null;
  }
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

  package._registeredMethods.forEach((methodName, f) {
    exports[methodName] = (arg) {
      var result = f(arg);
      if (result is Disposable) {
        // Convert the returned Disposable to a JS object.
        Map m = {'dispose': result.dispose};
        return jsify(m);
      } else if (result is List || result is Map) {
        return jsify(result);
      } else if (result is JsObject) {
        return result;
      } else {
        return null;
      }
    };
  });
  package._registeredMethods = null;
}

class Atom extends ProxyHolder {
  CommandRegistry _commands;
  Config _config;
  NotificationManager _notifications;
  PackageManager _packages;
  Project _project;
  ViewRegistry _views;
  Workspace _workspace;

  Atom() : super(_ctx) {
    _commands = new CommandRegistry(obj['commands']);
    _config = new Config(obj['config']);
    _notifications = new NotificationManager(obj['notifications']);
    _packages = new PackageManager(obj['packages']);
    _project = new Project(obj['project']);
    _views = new ViewRegistry(obj['views']);
    _workspace = new Workspace(obj['workspace']);
  }

  CommandRegistry get commands => _commands;
  Config get config => _config;
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
}

/// ViewRegistry handles the association between model and view types in Atom.
/// We call this association a View Provider. As in, for a given model, this
/// class can provide a view via [getView], as long as the model/view
/// association was registered via [addViewProvider].
class ViewRegistry extends ProxyHolder {
    ViewRegistry(JsObject object) : super(object);

  // TODO: expose addViewProvider(providerSpec)

  /// Get the view associated with an object in the workspace. The result is
  /// likely an html Element.
  dynamic getView(object) => invoke('getView', object);
}

/// Represents the state of the user interface for the entire window. Interact
/// with this object to open files, be notified of current and future editors,
/// and manipulate panes.
class Workspace extends ProxyHolder {
  Workspace(JsObject object) : super(object);

  /// Returns a list of [TextEditor]s.
  List<TextEditor> getTextEditors() =>
      invoke('getTextEditors').map((e) => new TextEditor(e)).toList();

  /// Get the active item if it is a [TextEditor].
  TextEditor getActiveTextEditor() {
    var result = invoke('getActiveTextEditor');
    return result == null ? null : new TextEditor(result);
  }

  /// Invoke the given callback with all current and future text editors in the
  /// workspace.
  Disposable observeTextEditors(void callback(TextEditor editor)) {
    var disposable = invoke('observeTextEditors', (ed) => callback(new TextEditor(ed)));
    return new JsDisposable(disposable);
  }

  Disposable observeActivePaneItem(void callback(dynamic item)) {
    // TODO: What type is the item?
    var disposable = invoke('observeActivePaneItem', (item) => callback(item));
    return new JsDisposable(disposable);
  }

  Panel addModalPanel({dynamic item, bool visible, int priority}) =>
      new Panel(invoke('addModalPanel', _panelOptions(item, visible, priority)));

  Panel addTopPanel({dynamic item, bool visible, int priority}) =>
      new Panel(invoke('addTopPanel', _panelOptions(item, visible, priority)));

  Panel addBottomPanel({dynamic item, bool visible, int priority}) =>
      new Panel(invoke('addBottomPanel', _panelOptions(item, visible, priority)));

  Panel addLeftPanel({dynamic item, bool visible, int priority}) =>
      new Panel(invoke('addLeftPanel', _panelOptions(item, visible, priority)));

  Panel addRightPanel({dynamic item, bool visible, int priority}) =>
      new Panel(invoke('addRightPanel', _panelOptions(item, visible, priority)));

  /// Opens the given URI in Atom asynchronously. If the URI is already open,
  /// the existing item for that URI will be activated. If no URI is given, or
  /// no registered opener can open the URI, a new empty TextEditor will be
  /// created.
  ///
  /// [options] can include initialLine, initialColumn, split, activePane, and
  /// searchAllPanes.
  Future<TextEditor> open(String url, {Map options}) {
    Future future = promiseToFuture(invoke('open', url, options));
    return future.then((result) {
      if (result == null) throw 'unable to open ${url}';
      TextEditor editor = new TextEditor(result);
      if (editor.isValid()) return editor;
      throw 'result is not a text editor';
    });
  }

  Map _panelOptions(dynamic item, bool visible, int priority) {
    Map options = {'item': item};
    if (visible != null) options['visible'] = visible;
    if (priority != null) options['priority'] = priority;
    return options;
  }
}

class Panel extends ProxyHolder {
  Panel(JsObject object) : super(object);

  Stream<bool> get onDidChangeVisible => eventStream('onDidChangeVisible');
  Stream<Panel> get onDidDestroy =>
      eventStream('onDidDestroy').map((obj) => new Panel(obj));

  bool isVisible() => invoke('isVisible');
  void show() => invoke('show');
  void hide() => invoke('hide');
  void destroy() => invoke('destroy');
}

class CommandRegistry extends ProxyHolder {
  CommandRegistry(JsObject object) : super(object);

  Disposable add(String target, String commandName, void callback(AtomEvent event)) {
    return new JsDisposable(
        invoke('add', target, commandName, (e) => callback(new AtomEvent(e))));
  }

  void dispatch(Element target, String commandName, {Map options}) =>
      invoke('dispatch', target, commandName, options);
}

class Config extends ProxyHolder {
  Config(JsObject object) : super(object);

  /// [keyPath] should be in the form `pluginid.keyid` - e.g. `${pluginId}.sdkLocation`.
  dynamic getValue(String keyPath, {scope}) {
    Map options;
    if (scope != null) options = {'scope': scope};
    return invoke('get', keyPath, options);
  }

  void setValue(String keyPath, dynamic value) => invoke('set', keyPath, value);

  /// Add a listener for changes to a given key path. This will immediately call
  /// your callback with the current value of the config entry.
  Disposable observe(String keyPath, Map options, void callback(value)) {
    if (options == null) options = {};
    return new JsDisposable(invoke('observe', keyPath, options, callback));
  }

  /// Add a listener for changes to a given key path.
  Stream<dynamic> onDidChange(String keyPath, [Map options]) {
    if (options == null) options = {};
    return eventStream2Args('onDidChangePaths', keyPath, options);
  }
}

/// A notification manager used to create notifications to be shown to the user.
class NotificationManager extends ProxyHolder {
  NotificationManager(JsObject object) : super(object);

  // TODO: Expose the `buttons` field.
  // https://github.com/atom/exception-reporting/blob/master/lib/reporter.coffee#L101

  /// Add an success notification. If [dismissable] is `true`, the notification
  /// is rendered with a close button and does not auto-close.
  void addSuccess(String message, {String detail, String description,
      bool dismissable, String icon}) {
    invoke('addSuccess', message, _options(detail: detail,
      description: description, dismissable: dismissable, icon: icon));
  }

  /// Add an informational notification.
  void addInfo(String message, {String detail, String description,
      bool dismissable, String icon}) {
    invoke('addInfo', message, _options(detail: detail,
      description: description, dismissable: dismissable, icon: icon));
  }

  /// Add an warning notification.
  void addWarning(String message, {String detail, String description,
      bool dismissable, String icon}) {
    invoke('addWarning', message, _options(detail: detail,
      description: description, dismissable: dismissable, icon: icon));
  }

  /// Add an error notification.
  void addError(String message, {String detail, String description,
      bool dismissable, String icon}) {
    invoke('addError', message, _options(detail: detail,
      description: description, dismissable: dismissable, icon: icon));
  }

  /// Add an fatal error notification.
  void addFatalError(String message, {String detail, String description,
      bool dismissable, String icon}) {
    invoke('addFatalError', message, _options(detail: detail,
      description: description, dismissable: dismissable, icon: icon));
  }

  Map _options({String detail, String description, bool dismissable, String icon}) {
    if (detail == null && description == null && dismissable == null && icon == null) {
      return null;
    }

    Map m = {};
    if (detail != null) m['detail'] = detail;
    if (description != null) m['description'] = description;
    if (dismissable != null) m['dismissable'] = dismissable;
    if (icon != null) m['icon'] = icon;
    return m;
  }
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
  List<String> getPackageDirPaths() => invoke('getPackageDirPaths');

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

  /// Fires an event when the file or directory's contents change.
  Stream get onDidChange => eventStream('onDidChange');

  String get path => obj['path'];

  bool isFile() => invoke('isFile');
  bool isDirectory() => invoke('isDirectory');
  bool existsSync() => invoke('existsSync');

  String getBaseName() => invoke('getBaseName');
  String getPath() => invoke('getPath');
  String getRealPathSync() => invoke('getRealPathSync');

  Directory getParent() => new Directory(invoke('getParent'));

  String toString() => path;
}

class File extends Entry {
  File(JsObject object) : super(object);
  File.fromPath(String path, [bool symlink]) :
      super(_create('File', path, symlink));

  Stream get onDidRename => eventStream('onDidRename');
  Stream get onDidDelete => eventStream('onDidDelete');

  /// Get the SHA-1 digest of this file.
  String getDigestSync() => invoke('getDigestSync');

  String getEncoding() => invoke('getEncoding');

  /// Reads the contents of the file. [flushCache] indicates whether to require
  /// a direct read or if a cached copy is acceptable.
  Future<String> read([bool flushCache]) =>
      promiseToFuture(invoke('read', flushCache));

  /// Reads the contents of the file. [flushCache] indicates whether to require
  /// a direct read or if a cached copy is acceptable.
  String readSync([bool flushCache]) => invoke('readSync', flushCache);

  /// Overwrites the file with the given text.
  void writeSync(String text) => invoke('writeSync', text);

  int get hashCode => path.hashCode;

  operator==(other) => other is File && path == other.path;
}

class Directory extends Entry {
  Directory(JsObject object) : super(object);
  Directory.fromPath(String path, [bool symlink]) :
      super(_create('Directory', path, symlink));

  /// Returns `true` if this [Directory] is the root directory of the
  /// filesystem, or `false` if it isn't.
  bool isRoot() => invoke('isRoot');

  // TODO: Should we move this _cvt guard into the File and Directory ctors?
  File getFile(filename) => new File(_cvt(invoke('getFile', filename)));
  Directory getSubdirectory(String dirname) =>
      new Directory(invoke('getSubdirectory', dirname));

  List<Entry> getEntriesSync() {
    return invoke('getEntriesSync').map((entry) {
      entry = _cvt(entry);
      return entry.callMethod('isFile') ? new File(entry) : new Directory(entry);
    }).toList();
  }

  /// Returns whether the given path (real or symbolic) is inside this directory.
  /// This method does not actually check if the path exists, it just checks if
  /// the path is under this directory.
  bool contains(String p) => invoke('contains', p);

  int get hashCode => path.hashCode;

  operator==(other) => other is Directory && path == other.path;
}

/// This cooresponds to an `atom-text-editor` custom element.
class TextEditorView extends ProxyHolder {
  TextEditorView(JsObject object) : super(_cvt(object));

  TextEditor getModel() => new TextEditor(invoke('getModel'));

  // num scrollTop() => invoke('scrollTop');
  // num scrollLeft() => invoke('scrollLeft');
}

class TextEditor extends ProxyHolder {
  TextEditor(JsObject object) : super(_cvt(object));

  /// Return whether this editor is a valid object. We sometimes create them
  /// from JS objects w/o knowning if they are editors for certain.
  bool isValid() {
    try {
      getTitle();
      getLongTitle();
      getPath();
      return true;
    } catch (e) {
      return false;
    }
  }

  TextBuffer getBuffer() => new TextBuffer(invoke('getBuffer'));

  String getTitle() => invoke('getTitle');
  String getLongTitle() => invoke('getLongTitle');
  String getPath() => invoke('getPath');
  bool isModified() => invoke('isModified');
  bool isEmpty() => invoke('isEmpty');
  bool isNotEmpty() => !isEmpty();

  void insertNewline() => invoke('insertNewline');

  void backspace() => invoke('backspace');

  /// Returns a [Range] when the text has been inserted. Returns a `bool`
  /// (`false`) when the text has not been inserted.
  ///
  /// For [options]: `select` if true, selects the newly added text.
  /// `autoIndent` if true, indents all inserted text appropriately.
  /// `autoIndentNewline` if true, indent newline appropriately.
  /// `autoDecreaseIndent` if true, decreases indent level appropriately (for
  /// example, when a closing bracket is inserted). `normalizeLineEndings`
  /// (optional) bool (default: true). `undo` if skip, skips the undo stack for
  /// this operation.
  dynamic insertText(String text, {Map options}) {
    var result = invoke('insertText', text, options);
    return result is bool ? result : new Range(result);
  }

  String selectAll() => invoke('selectAll');

  /// An ambiguous type:
  /// {
  ///   'scopes': ['source.dart']
  /// }
  ScopeDescriptor getRootScopeDescriptor() =>
      new ScopeDescriptor(invoke('getRootScopeDescriptor'));

  /// Get the syntactic scopeDescriptor for the given position in buffer
  /// coordinates.
  ScopeDescriptor scopeDescriptorForBufferPosition(Point bufferPosition) =>
      new ScopeDescriptor(invoke('scopeDescriptorForBufferPosition', bufferPosition));

  String getText() => invoke('getText');
  String getSelectedText() => invoke('getSelectedText');
  String getTextInBufferRange(Range range) => invoke('getTextInBufferRange', range);
  /// Get the [Range] of the most recently added selection in buffer coordinates.
  Range getSelectedBufferRange() => new Range(invoke('getSelectedBufferRange'));

  /// Set the selected range in buffer coordinates. If there are multiple
  /// selections, they are reduced to a single selection with the given range.
  void setSelectedBufferRange(Range bufferRange) =>
      invoke('setSelectedBufferRange', bufferRange);
  /// Set the selected ranges in buffer coordinates. If there are multiple
  /// selections, they are replaced by new selections with the given ranges.
  void setSelectedBufferRanges(List<Range> ranges) =>
      invoke('setSelectedBufferRanges', ranges.map((Range r) => r.obj).toList());

  Range getCurrentParagraphBufferRange() =>
      new Range(invoke('getCurrentParagraphBufferRange'));
  Range setTextInBufferRange(Range range, String text) =>
      new Range(invoke('setTextInBufferRange', range, text));

  /// Move the cursor to the given position in buffer coordinates.
  void setCursorBufferPosition(Point point) =>
      invoke('setCursorBufferPosition', point);
  void selectRight(columnCount) => invoke('selectRight', columnCount);

  String lineTextForBufferRow(int bufferRow) =>
      invoke('lineTextForBufferRow', bufferRow);

  void undo() => invoke('undo');
  void redo() => invoke('redo');

  dynamic createCheckpoint() => invoke('createCheckpoint');
  bool groupChangesSinceCheckpoint(checkpoint) => invoke('groupChangesSinceCheckpoint', checkpoint);
  bool revertToCheckpoint(checkpoint) => invoke('revertToCheckpoint', checkpoint);

  /// Perform the [fn] in one atomic, undoable transaction.
  void atomic(void fn()) {
    var checkpoint = createCheckpoint();
    try {
      fn();
      groupChangesSinceCheckpoint(checkpoint);
    } catch (e) {
      revertToCheckpoint(checkpoint);
      _logger.warning('transaction failed: ${e}');
    }
  }

  void save() => invoke('save');

  /// Calls your callback when the grammar that interprets and colorizes the
  /// text has been changed.
  /// Immediately calls your callback with the current grammar.
  Disposable observeGrammar(void callback(Grammar grammar)) {
    var disposable = invoke('observeGrammar', (g) => callback(new Grammar(g)));
    return new JsDisposable(disposable);
  }

  /// Determine if the given row is entirely a comment.
  bool isBufferRowCommented(int bufferRow) =>
      invoke('isBufferRowCommented', bufferRow);

  Point screenPositionForPixelPosition(Point position) =>
      invoke('screenPositionForPixelPosition', position);

  Point pixelPositionForScreenPosition(Point position) =>
      invoke('pixelPositionForScreenPosition', position);

  /// Convert a position in buffer-coordinates to screen-coordinates.
  Point screenPositionForBufferPosition(Point position) =>
      invoke('screenPositionForBufferPosition', position);

  /// Convert a position in screen-coordinates to buffer-coordinates.
  Point bufferPositionForScreenPosition(position) =>
      invoke('bufferPositionForScreenPosition', position);

  /// Invoke the given callback synchronously when the content of the buffer
  /// changes. Because observers are invoked synchronously, it's important not
  /// to perform any expensive operations via this method. Consider
  /// [onDidStopChanging] to delay expensive operations until after changes stop
  /// occurring.
  Stream get onDidChange => eventStream('onDidChange');

  /// Fire an event when the buffer's contents change. It is emitted
  /// asynchronously 300ms after the last buffer change. This is a good place to
  /// handle changes to the buffer without compromising typing performance.
  Stream get onDidStopChanging => eventStream('onDidStopChanging');

  /// Invoke the given callback when the editor is destroyed.
  Stream get onDidDestroy => eventStream('onDidDestroy');

  /// Invoke the given callback after the buffer is saved to disk.
  Stream get onDidSave => eventStream('onDidSave');

  // Return the editor's TextEditorView / <text-editor-view> / HtmlElement. This
  // view is an HtmlElement, but we can't use it as one. we need to access it
  // through JS interop.
  dynamic get view => atom.views.getView(obj);

  String toString() => getTitle();
}

class TextBuffer extends ProxyHolder {
  TextBuffer(JsObject object) : super(_cvt(object));

  String getPath() => invoke('getPath');

  int characterIndexForPosition(Point position) =>
      invoke('characterIndexForPosition', position);
  Point positionForCharacterIndex(int offset) =>
      new Point(invoke('positionForCharacterIndex', offset));

  /// Set the text in the given range. Returns the Range of the inserted text.
  Range setTextInRange(Range range, String text) =>
      new Range(invoke('setTextInRange', range, text));

  /// Create a pointer to the current state of the buffer for use with
  /// [groupChangesSinceCheckpoint] and [revertToCheckpoint].
  dynamic createCheckpoint() => invoke('createCheckpoint');
  /// Group all changes since the given checkpoint into a single transaction for
  /// purposes of undo/redo. If the given checkpoint is no longer present in the
  /// undo history, no grouping will be performed and this method will return
  /// false.
  bool groupChangesSinceCheckpoint(checkpoint) => invoke('groupChangesSinceCheckpoint', checkpoint);
  /// Revert the buffer to the state it was in when the given checkpoint was
  /// created. The redo stack will be empty following this operation, so changes
  /// since the checkpoint will be lost. If the given checkpoint is no longer
  /// present in the undo history, no changes will be made to the buffer and
  /// this method will return false.
  bool revertToCheckpoint(checkpoint) => invoke('revertToCheckpoint', checkpoint);

  /// Perform the [fn] in one atomic, undoable transaction.
  void atomic(void fn()) {
    var checkpoint = createCheckpoint();
    try {
      fn();
      groupChangesSinceCheckpoint(checkpoint);
    } catch (e) {
      revertToCheckpoint(checkpoint);
      _logger.warning('transaction failed: ${e}');
    }
  }

  /// Get the range for the given row. [row] is a number representing a
  /// 0-indexed row. [includeNewline] is a bool indicating whether or not to
  /// include the newline, which results in a range that extends to the start of
  /// the next line.
  Range rangeForRow(int row, bool includeNewline) =>
      new Range(invoke('rangeForRow', row, includeNewline));

  /// Invoke the given callback before the buffer is saved to disk.
  Stream get onWillSave => eventStream('onWillSave');
}

class Grammar extends ProxyHolder {
  Grammar(JsObject object) : super(_cvt(object));
}

/// Represents a region in a buffer in row / column coordinates.
class Range extends ProxyHolder {
  factory Range(JsObject object) => object == null ? null : new Range._(object);
  Range.fromPoints(Point start, Point end) : super(_create('Range', start.obj, end.obj));
  Range._(JsObject object) : super(_cvt(object));

  bool isEmpty() => invoke('isEmpty');
  bool isNotEmpty() => !isEmpty();
  bool isSingleLine() => invoke('isSingleLine');
  int getRowCount() => invoke('getRowCount');

  Point get start => new Point(obj['start']);
  Point get end => new Point(obj['end']);

  String toString() => invoke('toString');
}

/// Represents a point in a buffer in row / column coordinates.
class Point extends ProxyHolder {
  Point(JsObject object) : super(_cvt(object));
  Point.coords(int row, int column) : super(_create('Point', row, column));

  /// A zero-indexed Number representing the row of the Point.
  int get row => obj['row'];
  /// A zero-indexed Number representing the column of the Point.
  int get column => obj['column'];

  String toString() => invoke('toString');
}

class AtomEvent extends ProxyHolder {
  AtomEvent(JsObject object) : super(_cvt(object));

  dynamic get currentTarget => obj['currentTarget'];

  /// Return the editor that is the target of this event. Note, this is _only_
  /// available if an editor is the target of an event; calling this otherwise
  /// will return an invalid [TextEditor].
  TextEditor get editor {
    TextEditorView view = new TextEditorView(currentTarget);
    return view.getModel();
  }

  /// Return the currently selected file item. This call will only be meaningful
  /// if the event target is the Tree View.
  Element get selectedFileItem {
    Element element = currentTarget;
    return element.querySelector('li[is=tree-view-file].selected span.name');
  }

  /// Return the currently selected file path. This call will only be meaningful
  /// if the event target is the Tree View.
  String get selectedFilePath {
    Element element = selectedFileItem;
    return element == null ? null : element.getAttribute('data-path');
  }

  void abortKeyBinding() => invoke('abortKeyBinding');

  bool get keyBindingAborted => obj['keyBindingAborted'];

  void preventDefault() => invoke('preventDefault');

  bool get defaultPrevented => obj['defaultPrevented'];

  void stopPropagation() => invoke('stopPropagation');
  void stopImmediatePropagation() => invoke('stopImmediatePropagation');

  bool get propagationStopped => obj['propagationStopped'];
}

class Shell {
  Shell();

  JsObject get _shell => require('shell');

  openExternal(String url) => _shell.callMethod('openExternal', [url]);
}

class ScopeDescriptor extends ProxyHolder {
  factory ScopeDescriptor(JsObject object) {
    return object == null ? null : new ScopeDescriptor._(object);
  }
  ScopeDescriptor._(JsObject object) : super(object);

  List<String> get scopes => obj['scopes'];

  List<String> getScopesArray() => invoke('getScopesArray');
}

class BufferedProcess extends ProxyHolder {
  static BufferedProcess create(String command, {
      List<String> args,
      void stdout(String str),
      void stderr(String str),
      void exit(num code),
      String cwd,
      Map<String, String> env}) {
    Map options = {'command': command};

    if (args != null) options['args'] = args;
    if (stdout != null) options['stdout'] = stdout;
    if (stderr != null) options['stderr'] = stderr;
    if (exit != null) options['exit'] = exit;

    if (cwd != null || env != null) {
      Map nodeOptions = {};
      if (cwd != null) nodeOptions['cwd'] = cwd;
      if (env != null) nodeOptions['env'] = jsify(env);
      options['options'] = jsify(nodeOptions);
    }

    JsObject ctor = require('atom')['BufferedProcess'];
    return new BufferedProcess._(new JsObject(ctor, [jsify(options)]));
  }

  JsObject _stdin;

  BufferedProcess._(JsObject object) : super(object);

  /// Write the given string as utf8 bytes to the process' stdin.
  void write(String str) {
    // node.js ChildProcess, Writeable stream
    if (_stdin == null) _stdin = obj['process']['stdin'];
    _stdin.callMethod('write', [str, 'utf8']);
  }

  void kill() => invoke('kill');
}

JsObject _create(String className, dynamic arg1, [dynamic arg2]) {
  if (arg2 != null) {
    return new JsObject(require('atom')[className], [arg1, arg2]);
  } else {
    return new JsObject(require('atom')[className], [arg1]);
  }
}

JsObject _cvt(JsObject object) {
  if (object == null) return null;
  // TODO: We really shouldn't have to be wrapping objects we've already gotten
  // from JS interop.
  return new JsObject.fromBrowserObject(object);
}

Stats statSync(String path) =>
    new Stats(require('fs').callMethod('statSync', [path]));

class Stats extends ProxyHolder {
  Stats(JsObject obj) : super(obj);

  bool isFile() => invoke('isFile');
  bool isDirectory() => invoke('isDirectory');
}
