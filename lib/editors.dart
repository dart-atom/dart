// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.editors;

import 'dart:async';

import 'atom.dart';
import 'projects.dart';
import 'state.dart';
import 'utils.dart';

class EditorManager implements Disposable {
  static Duration _flashDuration = new Duration(milliseconds: 100);

  static Future flashSelection(TextEditor editor, Range range) async {
    Range original = editor.getSelectedBufferRange();
    editor.setSelectedBufferRange(range);
    await new Future.delayed(_flashDuration);
    editor.setSelectedBufferRange(original);
    return new Future.delayed(_flashDuration);
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
