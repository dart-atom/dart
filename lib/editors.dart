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
import 'impl/analysis_server_gen.dart' show LinkedEditGroup, Position, SourceEdit;

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

  final StreamController<TextEditor> _editorController = new StreamController.broadcast();
  final StreamController<File> _fileController = new StreamController.broadcast();

  Disposable _observe;

  EditorManager() {
    _observe = atom.workspace.observeActivePaneItem(_itemChanged);
  }

  TextEditor get activeEditor => atom.workspace.getActiveTextEditor();

  Stream<TextEditor> get onActiveEditorChanged => _editorController.stream;

  File get activeDartFile => _dartFileFrom(atom.workspace.getActiveTextEditor());

  Stream<File> get onDartFileChanged => _fileController.stream;

  void dispose() => _observe.dispose();

  void _itemChanged(item) {
    TextEditor editor = new TextEditor(item);
    if (editor.isValid()) {
      _editorController.add(editor);
      File file = _dartFileFrom(editor);
      if (file != null) _fileController.add(file);
    }
  }

  File _dartFileFrom(TextEditor editor) {
    if (editor == null) return null;
    String path = editor.getPath();
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return null;
    if (!project.isDartFile(path)) return null;
    return new File.fromPath(path);
  }
}
