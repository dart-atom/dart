// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.editing;

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/workspace.dart';
import 'package:logging/logging.dart';

final Logger _logger = new Logger('editing');

// TODO: Tests for this.

/// Handle special behavior for the enter key in Dart files. In particular, this
/// method extends dartdoc comments and block comments to the next line.
void handleEnterKey(AtomEvent event) {
  try {
    TextEditorElement view = new TextEditorElement(event.currentTarget);
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
  } else if (trimmedText.startsWith('//')) {
    inComment = (line.length - trimmedText.length + 1) <= col;
  } else if (trimmedText.startsWith('*')) {
    String temp = trimmedText.substring(1).trimLeft();
    leading = trimmedText.substring(1, trimmedText.length - temp.length);
    inComment = (line.length - trimmedText.length + 0) <= col;
  } else if (trimmedText.startsWith('/*')) {
    inComment = (line.length - trimmedText.length + 1) <= col;
  }

  if (!inComment) return false;
  if (leading.isEmpty) leading = ' ';

  String previousLine = editor.lineTextForBufferRow(row - 1)?.trimLeft() ?? '';
  String nextLine = editor.lineTextForBufferRow(row + 1)?.trimLeft() ?? '';

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

  if (trimmedText.startsWith('//')) {
    if (!atEol) {
      editor.atomic(() {
        editor.insertNewline();
        editor.insertText('// ');
      });

      return true;
    } else if (atEol) {
      var prefLineLength = atom.config.getValue('editor.preferredLineLength',
          scope: editor.getRootScopeDescriptor());

      if (col >= prefLineLength) {
        int wrapAtCol = line.substring(0, prefLineLength + 1).lastIndexOf(' ');
        int commentIndent = line.length - trimmedText.length;

        // We require the first space to be past the `// ` comment leader in
        // order to wrap. Otherwise look for a space after the line.
        if (wrapAtCol < commentIndent + 3) {
          wrapAtCol = line.indexOf(' ', prefLineLength);
        }

        editor.atomic(() {
          if (wrapAtCol >= 0) editor.moveLeft(col - wrapAtCol);
          editor.insertNewline();
          editor.insertText('// ');
          editor.moveToEndOfLine();
        });

        return true;
      }
    }

    return false;
  }

  if (trimmedText.startsWith('/*')) {
    if (nextLine.startsWith('*')) {
      editor.atomic(() {
        editor.insertNewline();
        editor.insertText(' * ');
      });
    } else {
      // Autoclose the comment.
      editor.atomic(() {
        editor.insertNewline();
        editor.insertText(' *${leading}');
        editor.insertNewline();
        editor.insertText('*/');
        editor.moveUp(1);
      });
    }

    return true;
  }

  if (trimmedText.endsWith('*/') && atEol) {
    editor.atomic(() {
      editor.insertNewline();
      // Only back up if we had some indentation on the current line.
      if (line != trimmedText) editor.backspace();
    });
    return true;
  }

  if (trimmedText.startsWith('*')) {
    if (row > 0) {
      if (previousLine.startsWith('/*') || previousLine.startsWith('*')) {
        editor.atomic(() {
          editor.insertNewline();
          editor.insertText('*${leading}');
        });

        return true;
      }
    }
  }

  // If we're not in a dartdoc or block comment, abort the key binding.
  return false;
}
