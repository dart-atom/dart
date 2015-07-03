// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.editors;

import 'dart:async';

import 'package:logging/logging.dart';

import 'atom.dart';
import 'projects.dart';
import 'state.dart';
import 'utils.dart';
import 'analysis/analysis_server_gen.dart' show LinkedEditGroup, Position, SourceEdit;

final Logger _logger = new Logger('editors');

class EditorManager implements Disposable {
  static Duration _flashDuration = new Duration(milliseconds: 100);

  static Future flashSelection(TextEditor editor, Range range) async {
    Range original = editor.getSelectedBufferRange();
    editor.setSelectedBufferRange(range);
    await new Future.delayed(_flashDuration);
    editor.setSelectedBufferRange(original);
    return new Future.delayed(_flashDuration);
  }

  /// Apply the given [SourceEdit]s in one atomic change.
  static void applyEdits(TextEditor editor, List<SourceEdit> edits) {
    sortEdits(edits);

    TextBuffer buffer = editor.getBuffer();
    buffer.createCheckpoint();

    try {
      edits.forEach((SourceEdit edit) {
        Range range = new Range.fromPoints(
          buffer.positionForCharacterIndex(edit.offset),
          buffer.positionForCharacterIndex(edit.offset + edit.length)
        );
        buffer.setTextInRange(range, edit.replacement);
      });

      buffer.groupChangesSinceCheckpoint();
    } catch (e) {
      buffer.revertToCheckpoint();
      _logger.warning('error applying source edits: ${e}');
    }
  }

  /// Select the given edit groups in the text editor.
  static void selectEditGroups(TextEditor editor, List<LinkedEditGroup> groups) {
    if (groups.isEmpty) return;

    // First, choose the bext group.
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
    List<Range> ranges = group.positions.map((Position position) {
      return new Range.fromPoints(
        buffer.positionForCharacterIndex(position.offset),
        buffer.positionForCharacterIndex(position.offset + group.length));
    }).toList();
    editor.setSelectedBufferRanges(ranges);
  }

  /// Sort [SourceEdit]s last-to-first.
  static void sortEdits(List<SourceEdit> edits) {
    edits.sort((SourceEdit a, SourceEdit b) => b.offset - a.offset);
  }

  Disposable _observe;

  String _dartFile;
  final StreamController<String> _dartFileController
      = new StreamController.broadcast();

  TextEditor _activeEditor;
  final StreamController<TextEditor> _editorActivateController
      = new StreamController.broadcast();
  final StreamController<TextEditor> _editorDeactivateController
      = new StreamController.broadcast();

  EditorManager() {
    _observe = atom.workspace.observeActivePaneItem(_itemChanged);
    Timer.run(_itemChanged);
  }

  /// Return the file for the current editor, if it is a dart file in a dart
  /// project.
  String get activeDartFile => _dartFile;

  /// Listen for changes to the active editor, if it is editing a dart file in a
  /// dart project.
  Stream<String> get onDartFileChanged => _dartFileController.stream;

  /// Return the current editor, if it is editing a `.dart` file. The file may or
  /// may not be in a dart project.
  TextEditor get currentDartEditor => _activeEditor;

  /// Listen for changes to the active editor, if it is editing a `.dart` file.
  /// The file may or may not be in a dart project.
  Stream<TextEditor> get onDartEditorActivated => _editorActivateController.stream;

  /// Listen for changes to the active editor, if it is editing a `.dart` file.
  /// The file may or may not be in a dart project.
  Stream<TextEditor> get onDartEditorDeactivated => _editorDeactivateController.stream;

  void dispose() => _observe.dispose();

  void _itemChanged([_]) {
    TextEditor editor = atom.workspace.getActiveTextEditor();

    if (editor == null) {
      _setCurrentItem(null);
      _setDartFile(null);
    } else {
      String path = editor.getPath();
      if (!isDartFile(path)) {
        _setCurrentItem(null);
        _setDartFile(null);
      } else {
        _setCurrentItem(editor);
        DartProject project = projectManager.getProjectFor(path);
        _setDartFile(project == null ? null : path);
      }
    }
  }

  void _setCurrentItem(TextEditor editor) {
    if (_activeEditor != null) _editorDeactivateController.add(_activeEditor);
    _activeEditor = editor;
    if (editor != null) _editorActivateController.add(editor);
  }

  void _setDartFile(String path) {
    if (_dartFile != path) {
      _dartFile = path;
      _dartFileController.add(path);
    }
  }
}
