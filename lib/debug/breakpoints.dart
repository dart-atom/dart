library atom.breakpoints;

import 'dart:async';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../projects.dart';
import '../state.dart';
import '../utils.dart';
import 'utils.dart';

final Logger _logger = new Logger('atom.breakpoints');

// TODO: persist breakpoints

// TODO: track changes to breakpoint files

// TODO: allow files outside the workspace?

// TODO: error message when they explicitely set a breakpoint, but not if an
// existing one fails to apply

// TODO: display executable location

// TODO: when setting breakpoints, adjust to where the VM actually set the
// breakpoint

// TODO: no breakpoints on ws or comment lines

class BreakpointManager implements Disposable {
  Disposables disposables = new Disposables();

  List<AtomBreakpoint> _breakpoints = [];
  List<_EditorBreakpoint> _editorBreakpoints = [];
  StreamController<AtomBreakpoint> _addController = new StreamController.broadcast();
  StreamController<AtomBreakpoint> _removeController = new StreamController.broadcast();

  BreakpointManager() {
    disposables.add(atom.commands.add('atom-workspace', 'dartlang:debug-toggle-breakpoint', (_) {
      _toggleBreakpoint();
    }));

    editorManager.dartEditors.openEditors.forEach(_processEditor);
    editorManager.dartEditors.onEditorOpened.listen(_processEditor);
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

  Stream<AtomBreakpoint> get onRemove => _removeController.stream;

  void _processEditor(TextEditor editor) {
    // Install any applicable breakpoints.
    getBreakpontsFor(editor.getPath()).forEach((AtomBreakpoint bp) {
      _createEditorBreakpoint(editor, bp);
    });
  }

  void _createEditorBreakpoint(TextEditor editor, AtomBreakpoint bp) {
    _logger.fine('creating editor breakpoint: ${bp}');
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

    // TODO: if the user has their cursor at the end of the line, they still
    // want the bp on that line
    Point p = editor.getCursorBufferPosition();
    AtomBreakpoint bp = new AtomBreakpoint(path, p.row + 1, column: p.column + 1);
    AtomBreakpoint other = _findSimilar(bp);

    // Check to see if we need to toggle it.
    if (other != null) {
      atom.notifications.addInfo('Removed breakpoint at ${other.display}.');
      removeBreakpoint(other);
    } else {
      atom.notifications.addSuccess('Added breakpoint at ${bp.display}.');
      addBreakpoint(bp);
    }
  }

  /// Find a breakpoint on the same file and line.
  AtomBreakpoint _findSimilar(AtomBreakpoint other) {
    return _breakpoints.firstWhere((bp) {
      return other.path == bp.path && other.line == bp.line;
    }, orElse: () => null);
  }

  void _removeEditorBreakpoint(_EditorBreakpoint bp) {
    _logger.fine('removing editor breakpoint: ${bp.bp}');
    _editorBreakpoints.remove(bp);
  }

  void dispose() => disposables.dispose();
}

class AtomBreakpoint {
  final String path;
  final int line;
  final int column;

  AtomBreakpoint(this.path, this.line, {this.column});

  String get asUrl => 'file://${path}';

  String get id => column == null ? '[${path}:${line}]' : '[${path}:${line}:${column}]';

  String get display {
    if (column == null) {
      return '${path}, line ${line}';
    } else {
      return '${path}, line ${line}, column ${column}';
    }
  }

  int get hashCode => id.hashCode;
  bool operator==(other) => other is AtomBreakpoint && id == other.id;

  String toString() => id;
}

class _EditorBreakpoint implements Disposable {
  final BreakpointManager manager;
  final TextEditor editor;
  final AtomBreakpoint bp;
  final Marker marker;

  StreamSubscription _sub;

  _EditorBreakpoint(this.manager, this.editor, this.bp, this.marker) {
    editor.decorateMarker(marker, {
      'type': 'line-number',
      'class': 'debugger-breakpoint'
    });

    _sub = marker.onDidDestroy.listen((_) {
      manager._removeEditorBreakpoint(this);
    });

    // TODO: on invalidate, remove the AtomBreakpoint

  }

  void dispose() {
    _sub.cancel();
    marker.destroy();
  }
}
