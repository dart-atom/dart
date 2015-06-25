// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.editing;

import 'package:logging/logging.dart';

import '../atom.dart';

final Logger _logger = new Logger('editing');

// TODO: If we're in a line comment, and the line is longer than the max line
// length, extend the comment.
// var prefLineLength = atom.config.get('editor.preferredLineLength',
//   scope: editor.getRootScopeDescriptor());

// TODO: If the line starts with `    ` continue the code block.

// TODO: Syntax highlighting of code blocks in dartdoc comments.

/// Handle special behavior for the enter key in Dart files. In particular, this
/// method extends dartdoc comments and block comments to the next line.
void handleEnterKey(AtomEvent event) {
  try {
    _handleEnterKey(event);
  } catch (e) {
    _logger.severe('exception during enter key handling: ${e}');
  }
}

void _handleEnterKey(AtomEvent event) {
  TextEditorView view = new TextEditorView(event.currentTarget);
  TextEditor editor = view.getModel();

  Range selection = editor.getSelectedBufferRange();

  // If the selection is not empty, abort the key binding.
  if (selection.isNotEmpty()) {
    event.abortKeyBinding();
    return;
  }

  int bufferRow = selection.start.row;
  String line = editor.lineTextForBufferRow(bufferRow);
  String trimmedText = line.trimLeft();

  if (trimmedText.startsWith('///')) {
    editor.insertNewline();
    editor.insertText('/// ');
    return;
  }

  if (trimmedText.startsWith('/*')) {
    editor.insertNewline();
    editor.insertText(' * ');
    return;
  }

  if (trimmedText.startsWith('* ')) {
    if (bufferRow > 0) {
      String previousLine = editor.lineTextForBufferRow(bufferRow - 1).trimLeft();

      if (previousLine.startsWith('/*') || previousLine.startsWith('* ')) {
        editor.insertNewline();
        editor.insertText('* ');
        return;
      }
    }
  }

  // If we're not in a dartdoc or block comment, abort the key binding.
  event.abortKeyBinding();
}
