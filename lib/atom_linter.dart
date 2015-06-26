// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// See the `linter` API [here](https://github.com/AtomLinter/linter).
library atom.linter;

import 'dart:async';
import 'dart:js';

import 'atom.dart';
import 'js.dart';

abstract class LinterProvider {
  final List<String> grammarScopes;
  final String scope;
  final bool lintOnFly;

  static void registerLinterProvider(String methodName, LinterProvider provider) {
    final JsObject exports = context['module']['exports'];
    exports[methodName] = () => provider.toProxy();
  }

  /// [grammarScopes] is a list of scopes, e.g. `['source.js', 'source.php']`.
  /// [scope] is one of either `file` or `project`. [lintOnFly] must be false
  /// for the scope `project`.
  LinterProvider({this.grammarScopes, this.scope, this.lintOnFly: false});

  Future<List<LintMessage>> lint(TextEditor editor);

  JsObject toProxy() {
    Map map = {
      'grammarScopes': grammarScopes,
      'scope': scope,
      'lintOnFly': lintOnFly,
      'lint': _lint
    };

    return jsify(map);
  }

  JsObject _lint(jsEditor) {
    TextEditor textEditor = new TextEditor(jsEditor);
    Future f = lint(textEditor).then((lints) {
      return lints.map((lint) => lint._toProxy()).toList();
    });
    Promise promise = new Promise.fromFuture(f);
    return promise.obj;
  }
}

class LintMessage {
  static const String ERROR = 'Error';
  static const String WARNING = 'Warning';
  static const String INFO = 'Info';

  final String type;
  final String text;
  final String html;
  final String filePath;
  final Rn range;
  // TODO: trace: ?array<Trace>

  LintMessage({this.type, this.text, this.html, this.filePath, this.range});

  Map _toMap() {
    Map m = {};
    if (type != null) m['type'] = type;
    if (text != null) m['text'] = text;
    if (html != null) m['html'] = html;
    if (filePath != null) m['filePath'] = filePath;
    if (range != null) m['range'] = range.toArray();
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
