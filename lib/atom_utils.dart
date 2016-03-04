// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.atom_utils;

import 'dart:async';
import 'dart:convert' show JSON;
import 'dart:html' show DivElement, Element, HttpRequest, Node, NodeValidator,
    NodeTreeSanitizer, window;
import 'dart:js';

import 'package:atom/node/process.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import 'atom.dart';
import 'js.dart';
import 'state.dart';

final Logger _logger = new Logger('atom_utils');

final JsObject _process = require('process');
final JsObject _fs = require('fs');

/// Get the value of an environment variable. This is often not accurate on the
/// mac since mac apps are launched in a different shell then the terminal
/// default.
String env(String key) {
  try {
    return _process['env'][key];
  } catch (err) {
    return null;
  }
}

/// Display a textual prompt to the user.
Future<String> promptUser(String prompt,
    {String defaultText, bool selectText: false, bool selectLastWord: false}) {
  if (defaultText == null) defaultText = '';

  // div, atom-text-editor.editor.mini div.message atom-text-editor[mini]
  Completer<String> completer = new Completer();
  Disposables disposables = new Disposables();

  Element element = new DivElement();
  element.setInnerHtml('''
    <label>${prompt}</label>
    <atom-text-editor mini>${defaultText}</atom-text-editor>
''',
      treeSanitizer: new TrustedHtmlTreeSanitizer());

  Element editorElement = element.querySelector('atom-text-editor');
  JsFunction editorConverter = context['getTextEditorForElement'];
  TextEditor editor = new TextEditor(editorConverter.apply([editorElement]));
  if (selectText) {
    editor.selectAll();
  } else if (selectLastWord) {
    editor.moveToEndOfLine();
    editor.selectToBeginningOfWord();
  }

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

/// Return a description of Atom, the plugin, and the OS.
Future<String> getSystemDescription({bool sdkPath: false}) {
  // 'Atom 1.0.11, dartlang 0.4.3, SDK 1.12 running on Windows.'
  String atomVer = atom.getVersion();
  String pluginVer;
  String sdkVer;
  String os = isMac ? 'macos' : process.platform;

  return getPackageVersion().then((ver) {
    pluginVer = ver;
    return sdkManager.hasSdk ? sdkManager.sdk.getVersion() : null;
  }).then((ver) {
    sdkVer = ver;

    String description = '\n\nAtom ${atomVer}, dartlang ${pluginVer}';
    if (sdkVer != null) description += ', SDK ${sdkVer}';
    description += ' running on ${os}.';

    if (sdkPath) {
      if (sdkManager.hasSdk) {
        description += '\nSDK at ${sdkManager.sdk.path}.';
      } else {
        description += '\nNo SDK configured.';
      }
    }

    return description;
  });
}

/// A [NodeValidator] which allows everything.
class PermissiveNodeValidator implements NodeValidator {
  bool allowsElement(Element element) => true;
  bool allowsAttribute(Element element, String attributeName, String value) {
    return true;
  }
}

class TrustedHtmlTreeSanitizer implements NodeTreeSanitizer {
  const TrustedHtmlTreeSanitizer();
  void sanitizeTree(Node node) { }
}

Future<Map> loadPackageJson() {
  return HttpRequest.getString('atom://dartlang/package.json').then((str) {
    return JSON.decode(str);
  });
}

Future<String> getPackageVersion() {
  return loadPackageJson().then((map) => map['version']);
}
