// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.analysis_server_dialog;

import 'dart:html' show DivElement, Element;

import '../atom.dart';
import '../state.dart';
import '../utils.dart';

class AnalysisServerDialog implements Disposable {
  final Disposables _disposables = new Disposables();

  Panel _panel;

  Element _messageElement;
  Element _statusElement;
  Element _startButton;
  Element _stopButton;

  AnalysisServerDialog() {
    _disposables.add(atom.commands.add('atom-workspace',
        'dart-lang:analysis-server-status', (_) => showDialog()));

    _disposables.add(atom.commands.add('atom-text-editor', 'core:cancel', (_) {
      if (_panel != null) _panel.hide();
    }));

    analysisServer.onActive.listen((val) => _updateStatus());
    analysisServer.onBusy.listen((val) => _updateStatus());
    analysisServer.onAllMessages.listen((message) {
      if (_messageElement != null && _panel != null) {
        _messageElement.text = '${message}';
      }
    });
  }

  void dispose() {
    _disposables.dispose();
    if (_panel != null) _panel.destroy();
  }

  void showDialog() {
    if (_panel != null) {
      _panel.show();
      return;
    }

    DivElement mainElement = new DivElement()..classes.add('analysis-dialog');

    Element title = new DivElement()
      ..classes.add('message')
      ..classes.add('title')
      ..classes.add('text-highlight')
      ..text = 'Analysis Server';
    mainElement.children.add(title);

    DivElement buttonGroup = new DivElement()..classes.add('block');
    buttonGroup.setAttribute('layout', '');
    buttonGroup.setAttribute('horizontal', '');
    mainElement.children.add(buttonGroup);

    _statusElement = new DivElement()..text = 'Status:';
    _statusElement.classes.add('inline-block-tight');
    _statusElement.setAttribute('flex', '');
    buttonGroup.children.add(_statusElement);

    _startButton = new Element.tag('button')
      ..classes.addAll(['btn', 'btn-sm', 'inline-block-tight']);
    _startButton.text = 'Start';
    _startButton.onClick.listen((_) => _handleServerStart());
    buttonGroup.children.add(_startButton);

    _stopButton = new Element.tag('button')
      ..classes.addAll(['btn', 'btn-sm', 'inline-block-tight']);
    _stopButton.text = 'Shutdown';
    _stopButton.onClick.listen((_) => _handleServerStop());
    buttonGroup.children.add(_stopButton);

    _messageElement = new DivElement()
      ..classes.add('last-message')
      ..classes.add('text-subtle');
    mainElement.children.add(_messageElement);

    _panel = atom.workspace.addModalPanel(item: mainElement);
    _panel.onDidDestroy.listen((_) {
      _panel = null;
    });

    _updateStatus();
  }

  void _updateStatus() {
    if (_statusElement == null) return;

    if (analysisServer.isBusy) {
      _statusElement.text = 'Status: analyzing…';
    } else if (analysisServer.isActive) {
      _statusElement.text = 'Status: idle';
    } else {
      _statusElement.text = 'Status: process not running';
    }

    if (analysisServer.isActive) {
      _startButton.setAttribute('disabled', '');
      _stopButton.attributes.remove('disabled');
    } else {
      _startButton.attributes.remove('disabled');
      _stopButton.setAttribute('disabled', '');
    }
  }

  void _handleServerStart() {
    analysisServer.start();
  }

  void _handleServerStop() {
    analysisServer.shutdown();
  }
}
