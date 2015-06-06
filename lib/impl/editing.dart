// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.editing;

import '../atom.dart';

/// Handle special behavior for the enter key in Dart files.
void handleEnterKey(AtomEvent event) {
  //TextEditorView view = new TextEditorView(event.currentTarget);
  //TextEditor editor = view.getModel();

  // TODO: check if we're in a dartdoc comment; if not, abort the key binding
  // TODO: is the selection is not empty, abort the key binding

  // TODO: if we're in a line comment, and the line is longer than the max line
  // length, then extent the comment.

  //print(editor.getTitle());
  event.abortKeyBinding();

  // editor.insertNewline();
  // editor.insertText('/// ');
}
