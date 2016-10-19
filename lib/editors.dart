// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.editors;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import 'analysis/analysis_server_lib.dart' show LinkedEditGroup, Position, SourceEdit;
import 'projects.dart';
import 'state.dart';

final Logger _logger = new Logger('editors');

final Duration _flashDuration = new Duration(milliseconds: 100);

Future flashSelection(TextEditor editor, Range range) async {
  Range original = editor.getSelectedBufferRange();
  editor.setSelectedBufferRange(range);
  await new Future.delayed(_flashDuration);
  editor.setSelectedBufferRange(original);
  return new Future.delayed(_flashDuration);
}

/// Apply the given [SourceEdit]s in one atomic change.
void applyEdits(TextEditor editor, List<SourceEdit> edits) {
  _sortEdits(edits);

  TextBuffer buffer = editor.getBuffer();

  buffer.atomic(() {
    edits.forEach((SourceEdit edit) {
      Range range = new Range.fromPoints(
        buffer.positionForCharacterIndex(edit.offset),
        buffer.positionForCharacterIndex(edit.offset + edit.length)
      );
      buffer.setTextInRange(range, edit.replacement);
    });
  });
}

/// Select the given edit groups in the text editor.
void selectEditGroups(TextEditor editor, List<LinkedEditGroup> groups) {
  if (groups.isEmpty) return;

  // First, choose the best group.
  LinkedEditGroup group = groups.first;
  int bestLength = group.positions.length;

  for (LinkedEditGroup g in groups) {
    if (g.positions.length > bestLength) {
      group = g;
      bestLength = group.positions.length;
    }
  }

  // Select group.
  TextBuffer buffer = editor.getBuffer();
  List<Range> ranges = new List.from(group.positions.map((Position position) {
    return new Range.fromPoints(
      buffer.positionForCharacterIndex(position.offset),
      buffer.positionForCharacterIndex(position.offset + group.length));
  }));
  editor.setSelectedBufferRanges(ranges);
}

/// Select the given edit group in the text editor.
void selectEditGroup(TextEditor editor, LinkedEditGroup group) {
  // Select group.
  TextBuffer buffer = editor.getBuffer();
  List<Range> ranges = new List.from(group.positions.map((Position position) {
    return new Range.fromPoints(
      buffer.positionForCharacterIndex(position.offset),
      buffer.positionForCharacterIndex(position.offset + group.length));
  }));
  editor.setSelectedBufferRanges(ranges);
}

/// Sort [SourceEdit]s last-to-first.
void _sortEdits(List<SourceEdit> edits) {
  edits.sort((SourceEdit a, SourceEdit b) => b.offset - a.offset);
}

class EditorManager implements Disposable {
  final Editors dartEditors = new Editors._allDartEditors();
  final Editors dartProjectEditors = new Editors._allDartEditors();
  // TODO: Fix this.
  //final Editors dartProjectEditors = new Editors._dartProjectEditors();

  EditorManager();

  Future<TextEditor> jumpToLocation(String path, [int line, int column, int length]) {
    Map options = { 'searchAllPanes': true };

    if (line != null) options['initialLine'] = line;
    if (column != null) options['initialColumn'] = column;

    // If we're editing the target file, then use the current editor.
    var ed = atom.workspace.getActiveTextEditor();
    if (ed != null && ed.getPath() == path) options['searchAllPanes'] = false;

    return atom.workspace.openPending(path, options: options).then((TextEditor editor) {
      if (length != null) editor.selectRight(length);
      return editor;
    });
  }

  Future<TextEditor> jumpToLine(String path, int line, {bool selectLine: true}) {
    Map options = { 'searchAllPanes': true };

    if (line != null) options['initialLine'] = line;

    // If we're editing the target file, then use the current editor.
    var ed = atom.workspace.getActiveTextEditor();
    if (ed != null && ed.getPath() == path) options['searchAllPanes'] = false;

    return atom.workspace.openPending(path, options: options).then((TextEditor editor) {
      if (selectLine) editor.selectLinesContainingCursors();
      return editor;
    });
  }

  void dispose() {
    dartEditors.dispose();
    dartProjectEditors.dispose();
  }
}

class Editors implements Disposable {
  static bool _isDartTypeEditor(TextEditor editor) {
    if (editor == null) return false;
    return isDartFile(editor.getPath());
  }

  static bool _isDartProjectEditor(TextEditor editor) {
    String path = editor.getPath();
    if (!isDartFile(path)) return false;
    DartProject project = projectManager.getProjectFor(path);
    return project != null;
  }

  Function _matches;
  Disposable _editorObserve;
  Disposable _itemObserve;

  StreamSubscriptions _subs = new StreamSubscriptions();

  final StreamController<TextEditor> _editorOpenedController = new StreamController.broadcast();
  final StreamController<TextEditor> _activeEditorController = new StreamController.broadcast();
  final StreamController<TextEditor> _editorClosedController = new StreamController.broadcast();

  TextEditor _activeEditor;
  List<TextEditor> _openEditors = [];

  Editors._allDartEditors() {
    _matches = _isDartTypeEditor;
    _editorObserve = atom.workspace.observeTextEditors(_observeTextEditors);
    _itemObserve = atom.workspace.observeActivePaneItem(_observeActivePaneItem);
  }

  Editors._dartProjectEditors() {
    _matches = _isDartProjectEditor;
    _editorObserve = atom.workspace.observeTextEditors(_observeTextEditors);
    _itemObserve = atom.workspace.observeActivePaneItem(_observeActivePaneItem);

    // TODO: Listen for project additions and deletions.

    // if (addedProjects.isNotEmpty) {
    //   List<TextEditor> editors = atom.workspace.getTextEditors().toList();
    //
    //   for (DartProject addedProject in addedProjects) {
    //     for (TextEditor editor in editors) {
    //       if (addedProject.contains(editor.getPath())) {
    //         _handleNewEditor(editor);
    //       }
    //     }
    //   }
    // }
  }

  TextEditor get activeEditor => _activeEditor;

  List<TextEditor> get openEditors => _openEditors;

  TextEditor getEditorForPath(String path) {
    return _openEditors.firstWhere(
        (editor) => editor.getPath() == path, orElse: () => null);
  }

  Stream<TextEditor> get onEditorOpened => _editorOpenedController.stream;

  Stream<TextEditor> get onActiveEditorChanged => _activeEditorController.stream;

  Stream<TextEditor> get onEditorClosed => _editorClosedController.stream;

  void dispose() {
    _editorObserve.dispose();
    _itemObserve.dispose();
    _subs.cancel();
  }

  void _observeTextEditors(TextEditor editor) {
    if (_matches(editor)) {
      _openEditors.add(editor);
      _editorOpenedController.add(editor);
      StreamSubscription sub;
      sub = editor.onDidDestroy.listen((_) {
        _subs.remove(sub);
        _openEditors.remove(editor);
        _editorClosedController.add(editor);
      });
      _subs.add(sub);
    }
  }

  void _observeActivePaneItem([_]) {
    TextEditor editor = atom.workspace.getActiveTextEditor();
    if (!_matches(editor)) editor = null;
    _activeEditor = editor;
    _activeEditorController.add(_activeEditor);
  }
}
