library atom.breakpoints;

import 'dart:async';
import 'dart:html' as html show Element, MouseEvent;

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../projects.dart';
import '../state.dart';
import 'utils.dart';

final Logger _logger = new Logger('atom.breakpoints');

// TODO: Allow files outside the workspace?

// TODO: Error message when they explicitly set a breakpoint, but not if an
// existing one fails to apply.

// TODO: When setting breakpoints, adjust to where the VM actually set the breakpoint.

// TODO: No breakpoints on ws or comment lines.

enum ExceptionBreakType {
  all,
  uncaught,
  none
}

const String _debuggerCaughtExceptions = 'dartlang.debuggerCaughtExceptions';

class BreakpointManager implements Disposable, StateStorable {
  Disposables disposables = new Disposables();
  StreamSubscriptions subs = new StreamSubscriptions();

  List<AtomBreakpoint> _breakpoints = [];
  List<_EditorBreakpoint> _editorBreakpoints = [];

  StreamController<AtomBreakpoint> _addController = new StreamController.broadcast();
  StreamController<AtomBreakpoint> _changeController = new StreamController.broadcast();
  StreamController<AtomBreakpoint> _removeController = new StreamController.broadcast();

  StreamController<ExceptionBreakType> _exceptionController = new StreamController.broadcast();

  _GutterTracker _gutterTracker;

  BreakpointManager() {
    disposables.add(atom.commands.add('atom-workspace', 'dartlang:debug-toggle-breakpoint', (_) {
      _toggleBreakpoint();
    }));
    subs.add(atom.config.onDidChange(_debuggerCaughtExceptions).listen((String val) {
      if (val == 'all') _exceptionController.add(ExceptionBreakType.all);
      else if (val == 'none') _exceptionController.add(ExceptionBreakType.none);
      else _exceptionController.add(ExceptionBreakType.uncaught);
    }));

    editorManager.dartEditors.openEditors.forEach(_processEditor);
    editorManager.dartEditors.onEditorOpened.listen(_processEditor);

    _updateGutterTracker(atom.workspace.getActiveTextEditor());
    editorManager.dartEditors.onActiveEditorChanged.listen(_updateGutterTracker);

    state.registerStorable('breakpoints', this);
  }

  void addBreakpoint(AtomBreakpoint breakpoint) {
    _breakpoints.add(breakpoint);
    _addController.add(breakpoint);

    for (TextEditor editor in editorManager.dartEditors.openEditors) {
      if (editor.getPath() == breakpoint.path) {
        _createEditorBreakpoint(editor, breakpoint);
      }
    }
  }

  List<AtomBreakpoint> get breakpoints => new List.from(_breakpoints);

  Iterable<AtomBreakpoint> getBreakpontsFor(String path) {
    return _breakpoints.where((bp) => bp.path == path);
  }

  void removeBreakpoint(AtomBreakpoint breakpoint) {
    _breakpoints.remove(breakpoint);
    _removeController.add(breakpoint);

    for (_EditorBreakpoint editorBreakpoint in _editorBreakpoints.toList()) {
      if (editorBreakpoint.bp == breakpoint) {
        _removeEditorBreakpoint(editorBreakpoint);
        editorBreakpoint.dispose();
      }
    }
  }

  Stream<AtomBreakpoint> get onAdd => _addController.stream;

  /// Fired when a breakpoint changes position (line or column).
  Stream<AtomBreakpoint> get onChange => _changeController.stream;

  Stream<AtomBreakpoint> get onRemove => _removeController.stream;

  ExceptionBreakType get breakOnExceptionType {
    String val = atom.config.getValue(_debuggerCaughtExceptions);
    if (val == 'all') return ExceptionBreakType.all;
    else if (val == 'none') return ExceptionBreakType.none;
    return ExceptionBreakType.uncaught;
  }

  set breakOnExceptionType(ExceptionBreakType val) {
    if (val == ExceptionBreakType.all) atom.config.setValue(_debuggerCaughtExceptions, 'all');
    else if (val == ExceptionBreakType.none) atom.config.setValue(_debuggerCaughtExceptions, 'none');
    else atom.config.setValue(_debuggerCaughtExceptions, 'uncaught');
  }

  Stream<ExceptionBreakType> get onBreakOnExceptionTypeChanged => _exceptionController.stream;

  void _processEditor(TextEditor editor) {
    // Install any applicable breakpoints.
    getBreakpontsFor(editor.getPath()).forEach((AtomBreakpoint bp) {
      _createEditorBreakpoint(editor, bp);
    });
  }

  void _updateGutterTracker(TextEditor editor) {
    _gutterTracker?.dispose();
    _gutterTracker = null;

    if (editor != null) {
      _gutterTracker = new _GutterTracker(this, editor);
    }
  }

  void _createEditorBreakpoint(TextEditor editor, AtomBreakpoint bp) {
    _logger.finer('creating editor breakpoint: ${bp}');
    Marker marker = editor.markBufferRange(
        debuggerCoordsToEditorRange(bp.line, bp.column),
        persistent: false);
    _editorBreakpoints.add(new _EditorBreakpoint(this, editor, bp, marker));
  }

  void _toggleBreakpoint() {
    TextEditor editor = atom.workspace.getActiveTextEditor();

    if (editor == null) {
      atom.beep();
      return;
    }

    String path = editor.getPath();
    if (!isDartFile(path)) {
      atom.notifications.addWarning('Breakpoints only supported for Dart files.');
      return;
    }

    // For now, we just create line breakpoints; use the column (`p.column`)
    // when we have a context menu item.
    Point p = editor.getCursorBufferPosition();
    AtomBreakpoint bp = new AtomBreakpoint(path, p.row + 1);
    AtomBreakpoint other = _findSimilar(bp);

    // Check to see if we need to toggle it.
    if (other != null) {
      removeBreakpoint(other);
    } else {
      addBreakpoint(bp);
    }
  }

  void _toggleLineNumberBreakpoint(TextEditor editor, int lineNumber) {
    String path = editor.getPath();
    if (!isDartFile(path)) {
      atom.notifications.addWarning('Breakpoints only supported for Dart files.');
      return;
    }

    AtomBreakpoint bp = new AtomBreakpoint(path, lineNumber + 1);
    AtomBreakpoint other = _findSimilar(bp);

    // Check to see if we need to toggle it.
    if (other != null) {
      removeBreakpoint(other);
    } else {
      addBreakpoint(bp);
    }
  }

  /// Find a breakpoint on the same file and line.
  AtomBreakpoint _findSimilar(AtomBreakpoint other) {
    return _breakpoints.firstWhere((AtomBreakpoint bp) {
      return other.path == bp.path && other.line == bp.line;
    }, orElse: () => null);
  }

  void _removeEditorBreakpoint(_EditorBreakpoint bp) {
    _logger.finer('removing editor breakpoint: ${bp.bp}');
    _editorBreakpoints.remove(bp);
  }

  void _updateBreakpointLocation(AtomBreakpoint bp, Range range) {
    LineColumn lineCol = editorRangeToDebuggerCoords(range);
    bp.updateLocation(lineCol);
    _changeController.add(bp);
  }

  void initFromStored(dynamic storedData) {
    if (storedData is List) {
      for (var json in storedData) {
        AtomBreakpoint bp = new AtomBreakpoint.fromJson(json);
        if (bp.fileExists()) addBreakpoint(bp);
      }

      _logger.fine('restored ${_breakpoints.length} breakpoints');
    }
  }

  dynamic toStorable() {
    return _breakpoints.map((AtomBreakpoint bp) => bp.toJsonable()).toList();
  }

  void dispose() {
    disposables.dispose();
    subs.dispose();
    _gutterTracker?.dispose();
  }
}

class AtomBreakpoint implements Comparable {
  final String path;
  int _line;
  int _column;

  AtomBreakpoint(this.path, int line, {int column}) {
    _line = line;
    _column = column;
  }

  AtomBreakpoint.fromJson(json) :
      path = json['path'], _line = json['line'], _column = json['column'];

  int get line => _line;
  int get column => _column;

  String get asUrl => 'file://${path}';

  String get id => column == null ? '[${path}:${line}]' : '[${path}:${line}:${column}]';

  String get display {
    if (column == null) {
      return '${getWorkspaceRelativeDescription(path)}, ${line}';
    } else {
      return '${getWorkspaceRelativeDescription(path)}, ${line}:${column}';
    }
  }

  /// Return whether the file associated with this breakpoint exists.
  bool fileExists() => fs.existsSync(path);

  void updateLocation(LineColumn lineCol) {
    _line = lineCol.line;
    _column = lineCol.column;
  }

  int get hashCode => id.hashCode;
  bool operator==(other) => other is AtomBreakpoint && id == other.id;

  Map toJsonable() {
    if (column == null) {
      return {'path': path, 'line': line};
    } else {
      return {'path': path, 'line': line, 'column': column};
    }
  }

  String toString() => id;

  int compareTo(other) {
    if (other is! AtomBreakpoint) return -1;

    int val = path.compareTo(other.path);
    if (val != 0) return val;

    val = line - other.line;
    if (val != 0) return val;

    int col_a = column == null ? -1 : column;
    int col_b = other.column == null ? -1 : other.column;
    return col_a - col_b;
  }
}

class _GutterTracker implements Disposable {
  final BreakpointManager breakpointManager;
  final TextEditor editor;

  StreamSubscription _sub;
  Disposable _gutterDisposable;
  StreamSubscription _gutterClickListener;

  _GutterTracker(this.breakpointManager, this.editor) {
    _initLineNumberGutter(editor.gutterWithName('line-number'));
    _sub = editor.onDidAddGutter.listen((Gutter gutter) {
      if (gutter.name == 'line-number') _initLineNumberGutter(gutter);
    });
  }

  void _initLineNumberGutter(Gutter gutter) {
    if (gutter == null || _gutterDisposable != null) return;

    // Listen for clicks.
    html.Element gutterElement = atom.views.getView(gutter);
    _gutterClickListener = gutterElement.onClick.listen((html.MouseEvent e) {
      html.Element div = e.target;
      var bufferRow = div.attributes['data-buffer-row'];
      if (bufferRow != null) {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        breakpointManager._toggleLineNumberBreakpoint(editor, int.parse(bufferRow));
      }
    });

    _gutterDisposable = gutter.onDidDestroy(() {
      _gutterClickListener?.cancel();
      _gutterDisposable = null;
    });
  }

  void dispose() {
    _sub.cancel();
    _gutterClickListener?.cancel();
    _gutterDisposable?.dispose();
  }
}

class _EditorBreakpoint implements Disposable {
  final BreakpointManager manager;
  final TextEditor editor;
  final AtomBreakpoint bp;
  final Marker marker;

  Range _range;

  StreamSubscriptions subs = new StreamSubscriptions();

  _EditorBreakpoint(this.manager, this.editor, this.bp, this.marker) {
    _range = marker.getBufferRange();

    editor.decorateMarker(marker, {
      'type': 'line-number',
      'class': 'debugger-breakpoint'
    });

    subs.add(marker.onDidChange.listen((e) {
      if (!marker.isValid()) {
        manager.removeBreakpoint(bp);
      } else {
        _checkForLocationChange();
      }
    }));
  }

  void _checkForLocationChange() {
    Range newRange = marker.getBufferRange();
    if (_range != newRange) {
      _range = newRange;
      manager._updateBreakpointLocation(bp, newRange);
    }
  }

  void dispose() {
    subs.cancel();
    marker.destroy();
  }
}
