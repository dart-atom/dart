// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// See the `linter-plus` API [here](https://github.com/AtomLinter/linter-plus).
library atom.linter;

import 'dart:async';
import 'dart:js';

import 'atom.dart';
import 'js.dart';

// Note: `linter-plus` will soon be renamed to `linter`.

abstract class LinterProvider {
  final List<String> scopes;
  final String scope;
  final bool lintOnFly;

  static void registerLinterProvider(String methodName, LinterProvider provider) {
    final JsObject exports = context['module']['exports'];
    exports[methodName] = () => provider.toProxy();
  }

  /// [scopes] is a list of scopes, e.g. `['source.js', 'source.php']`. [scope]
  /// is one of either `file` or `project`. [lintOnFly] must be false for the
  /// scope `project`.
  LinterProvider({this.scopes, this.scope, this.lintOnFly: false});

  Future<List<LintMessage>> lint(TextEditor editor, TextBuffer buffer);

  JsObject toProxy() {
    Map map = {
      'scopes': scopes,
      'scope': scope,
      'lintOnFly': lintOnFly,
      'lint': _lint
    };

    return jsify(map);
  }

  JsObject _lint(jsEditor, jsBuffer) {
    TextEditor editor = new TextEditor(jsEditor);
    TextBuffer buffer = new TextBuffer(jsBuffer);
    Future f = lint(editor, buffer).then((lints) {
      return lints.map((lint) {
        //print(lint._toMap());
        return lint._toProxy();
      }).toList();
    });
    Promise promise = new Promise.fromFuture(f);
    return promise.obj;
  }
}

class LintMessage {
  static const String ERROR = 'Error';
  static const String WARNING = 'Warning';

  final String type;
  final String message;
  final String html;
  final String file;
  final Rn position;

  LintMessage({this.type, this.message, this.html, this.file, this.position});

  Map _toMap() {
    Map m = {};
    if (type != null) m['type'] = type;
    if (message != null) m['message'] = message;
    if (html != null) m['html'] = html;
    if (file != null) m['file'] = file;
    if (position != null) m['position'] = position.toArray();
    return m;
  }

  JsObject _toProxy() => jsify(_toMap());
}

class Rn {
  final Pt start;
  final Pt end;

  Rn(this.start, this.end);

  List toArray() => [start.toArray(), end.toArray()];
}

class Pt {
  final int row;
  final int column;

  Pt(this.row, this.column);

  List toArray() => [row, column];
}
