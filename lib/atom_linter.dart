// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// See the `linter` API [here](https://github.com/AtomLinter/linter).
library atom.linter;

import 'dart:async';
import 'dart:js';

import 'package:atom/node/workspace.dart';
import 'package:atom/src/js.dart';

abstract class LinterProvider {
  final List<String> grammarScopes;
  final String scope;
  final bool lintOnFly;

  final JsObject _key = jsify({'scope': 'project'});

  static void registerLinterProvider(
      String methodName, LinterProvider provider) {
    final JsObject exports = context['module']['exports'];
    exports[methodName] = () => provider.toProxy();
  }

  /// [grammarScopes] is a list of scopes, e.g. `['source.js', 'source.php']`.
  /// [scope] is one of either `file` or `project`. [lintOnFly] must be false
  /// for the scope `project`.
  LinterProvider({this.grammarScopes, this.scope, this.lintOnFly: false});

  // A unique identifier for the provider; JS will store this in a hashmap as a
  // map key;
  Object get key => _key;

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

  JsObject _lint(jsEditor) => jsify([]);
}

abstract class LinterConsumer {
  void consume(LinterService linterService);
}

class LinterService extends ProxyHolder {
  LinterService(obj) : super(obj);

  void deleteMessages(LinterProvider provider) {
    invoke('deleteMessages', provider.key);
  }

  void setMessages(LinterProvider provider, List<LintMessage> messages) {
    // jsify(messages, deep: true) ?
    // jsifyIterable(messages) ?
    var list = messages.map((m) => m.toMap()).toList();
    invoke('setMessages', provider.key, list);
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

  LintMessage({this.type, this.text, this.html, this.filePath, this.range});

  Map toMap() {
    Map m = {};
    if (type != null) m['type'] = type;
    if (text != null) m['text'] = text;
    if (html != null) m['html'] = html;
    if (filePath != null) m['filePath'] = filePath;
    if (range != null) m['range'] = range.toArray();
    return m;
  }
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
