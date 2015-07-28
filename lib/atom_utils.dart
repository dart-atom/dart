// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.atom_utils;

import 'dart:async';
import 'dart:html' show DivElement, Element, NodeValidator, NodeTreeSanitizer, window;
import 'dart:js';

import 'package:logging/logging.dart';

import 'atom.dart';
import 'js.dart';
import 'utils.dart';

final Logger _logger = new Logger('atom_utils');

final JsObject _process = require('process');
final JsObject _fs = require('fs');

/// 'darwin', 'freebsd', 'linux', 'sunos' or 'win32'
final String platform = _process['platform'];

final bool isWindows = platform.startsWith('win');
final bool isMac = platform == 'darwin';
final bool isLinux = !isWindows && !isMac;

final String separator = isWindows ? '\\' : '/';

String join(dir, String arg1, [String arg2, String arg3]) {
  if (dir is Directory) dir = dir.path;
  String path = '${dir}${separator}${arg1}';
  if (arg2 != null) {
    path = '${path}${separator}${arg2}';
    if (arg3 != null) path = '${path}${separator}${arg3}';
  }
  return path;
}

String dirname(entry) {
  if (entry is Entry) return entry.getParent().path;
  int index = entry.lastIndexOf(separator);
  return index == -1 ? null : entry.substring(0, index);
}

/// Relative path entries are removed and symlinks are resolved to their final
/// destination.
String realpathSync(String path) => _fs.callMethod('realpathSync', [path]);

/// Get the value of an environment variable. This is often not accurate on the
/// mac since mac apps are launched in a different shell then the terminal
/// default.
String env(String key) => _process['env'][key];

/// Display a textual prompt to the user.
Future<String> promptUser({String prompt: '', String defaultText: '',
    bool selectText: false}) {
  // div, atom-text-editor.editor.mini div.message atom-text-editor[mini]
  Completer<String> completer = new Completer();
  Disposables disposables = new Disposables();

  Element element = new DivElement();
  element.setInnerHtml('''
    <atom-text-editor mini>${defaultText}</atom-text-editor>
    <div class="message">${prompt}</div>
''',
      validator: new PermissiveNodeValidator(),
      treeSanitizer: NodeTreeSanitizer.trusted);

  Element editorElement = element.querySelector('atom-text-editor');
  JsFunction editorConverter = context['getTextEditorForElement'];
  TextEditor editor = new TextEditor(editorConverter.apply([editorElement]));
  if (selectText) editor.selectAll();
  // Focus the element.
  Timer.run(() {
    try { editorElement.focus(); }
    catch (e) { _logger.warning(e); }
  });

  disposables.add(atom.commands.add('atom-workspace', 'core:confirm', (_) {
    if (!completer.isCompleted) completer.complete(editor.getText());
  }));

  disposables.add(atom.commands.add('atom-workspace', 'core:cancel', (_) {
    if (!completer.isCompleted) completer.complete(null);
  }));

  Panel panel = atom.workspace.addModalPanel(item: element, visible: true);

  completer.future.whenComplete(() {
    disposables.dispose();
    panel.destroy();
  });

  return completer.future;
}

/// A [NodeValidator] which allows everything.
class PermissiveNodeValidator implements NodeValidator {
  bool allowsElement(Element element) => true;
  bool allowsAttribute(Element element, String attributeName, String value) {
    return true;
  }
}
