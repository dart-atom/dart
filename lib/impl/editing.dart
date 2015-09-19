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

// TODO: Tests for this.

/// Handle special behavior for the enter key in Dart files. In particular, this
/// method extends dartdoc comments and block comments to the next line.
void handleEnterKey(AtomEvent event) {
  try {
    TextEditorView view = new TextEditorView(event.currentTarget);
    TextEditor editor = view.getModel();
    Range selection = editor.getSelectedBufferRange();

    // If the selection is not empty, abort the key binding.
    if (selection.isNotEmpty()) {
      event.abortKeyBinding();
    } else {
      int row = selection.start.row;
      if (editor.isBufferRowCommented(row) != true) {
        event.abortKeyBinding();
      } else {
        int col = selection.start.column;
        bool handled = _handleEnterKey(editor, row, col);
        if (!handled) event.abortKeyBinding();
      }
    }
  } catch (e) {
    event.abortKeyBinding();
    _logger.severe('exception during enter key handling', e);
  }
}

bool _handleEnterKey(TextEditor editor, int row, int col) {
  col--;

  String line = editor.lineTextForBufferRow(row);
  String trimmedText = line.trimLeft();

  bool inComment = false;
  bool atEol = (col + 1) == line.length;

  // Extend the leading whitespace to the next line.
  String leading = ' ';
  if (trimmedText.startsWith('///')) {
    String temp = trimmedText.substring(3).trimLeft();
    leading = trimmedText.substring(3, trimmedText.length - temp.length);
    inComment = (line.length - trimmedText.length + 2) <= col;
  } else if (trimmedText.startsWith('*')) {
    String temp = trimmedText.substring(1).trimLeft();
    leading = trimmedText.substring(1, trimmedText.length - temp.length);
    inComment = (line.length - trimmedText.length + 0) <= col;
  } else if (trimmedText.startsWith('/*')) {
    inComment = (line.length - trimmedText.length + 1) <= col;
  }

  if (!inComment) return false;
  if (leading.isEmpty) leading = ' ';

  String previousLine = '';
  if (row > 0) {
    previousLine = editor.lineTextForBufferRow(row - 1).trimLeft();
  }

  if (trimmedText.startsWith('///')) {
    if (trimmedText == '/// /' && atEol) {
      editor.atomic(() {
        editor.backspace();
        editor.backspace();
        editor.backspace();
        editor.backspace();
        editor.backspace();
      });
    } else {
      editor.atomic(() {
        editor.insertNewline();
        editor.insertText('///${leading}');
      });
    }
    return true;
  }

  if (trimmedText.startsWith('/*')) {
    editor.atomic(() {
      editor.insertNewline();
      editor.insertText(' * ');
    });
    return true;
  }

  if (trimmedText.endsWith('*/') && atEol) {
    editor.atomic(() {
      editor.insertNewline();
      editor.backspace();
    });
    return true;
  }

  if (trimmedText.startsWith('*')) {
    if (row > 0) {
      if (previousLine.startsWith('/*') || previousLine.startsWith('*')) {
        if (trimmedText.endsWith('* /')) {
          editor.atomic(() {
            editor.backspace();
            editor.backspace();
            editor.insertText('/');
            editor.insertNewline();
            editor.backspace();
          });
        } else if (trimmedText.endsWith(' /') && atEol) {
          editor.atomic(() {
            editor.backspace();
            editor.insertNewline();
            editor.insertText('*/');
          });
        } else {
          editor.atomic(() {
            editor.insertNewline();
            editor.insertText('*${leading}');
          });
        }

        return true;
      }
    }
  }

  // If we're not in a dartdoc or block comment, abort the key binding.
  return false;
}
