// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.analysis_server_dialog;

import '../atom.dart';
import '../elements.dart';
import '../state.dart';
import '../utils.dart';

class AnalysisServerDialog implements Disposable {
  final Disposables _disposables = new Disposables();

  Panel _panel;

  CoreElement _messageElement;
  CoreElement _statusElement;
  CoreElement _startButton;
  CoreElement _reanalyzeButton;
  CoreElement _stopButton;

  AnalysisServerDialog() {
    _disposables.add(atom.commands.add('atom-workspace',
        'dartlang:analysis-server-status', (_) => showDialog()));

    _disposables.add(atom.commands.add('atom-workspace', 'core:cancel', (_) {
      if (_panel != null) _panel.hide();
    }));

    analysisServer.onActive.listen((val) => _updateStatus());
    analysisServer.onBusy.listen((val) => _updateStatus());
    analysisServer.onSend.listen(_logTraffic);
    analysisServer.onReceive.listen(_logTraffic);
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

    CoreElement main = div(c: 'analysis-dialog')..add([
      div(text: 'Analysis Server', c: 'message title text-highlight'),
      div(c: 'block')..layoutHorizontal()..add([
        _statusElement = div(text: 'Status:')..flex()..inlineBlockTight(),
        _startButton = button(text: 'Start', c: 'btn btn-sm')..inlineBlockTight()
            ..click(_handleServerStart),
        _reanalyzeButton = button(text: 'Reanalyze', c: 'btn btn-sm')
            ..inlineBlockTight()..click(_handleReanalyze),
        _stopButton = button(text: 'Shutdown', c: 'btn btn-sm')..inlineBlockTight()
            ..click(_handleServerStop)
      ]),
      _messageElement = div(c: 'last-message text-subtle')
    ]);

    _panel = atom.workspace.addModalPanel(item: main.element);
    _panel.onDidDestroy.listen((_) => _panel = null);

    _updateStatus();
  }

  void _logTraffic(String message) {
    if (_messageElement != null && _panel != null) {
      if (message.length > 300) message = '${message.substring(0, 300)}…';
      _messageElement.text = '${message}';
    }
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

    _startButton.toggleAttribute('disabled', analysisServer.isActive);
    _reanalyzeButton.toggleAttribute('disabled', !analysisServer.isActive);
    _stopButton.toggleAttribute('disabled', !analysisServer.isActive);
  }

  void _handleServerStart() {
    analysisServer.start();
  }

  void _handleReanalyze() {
    analysisServer.reanalyzeSources();
  }

  void _handleServerStop() {
    analysisServer.shutdown();
  }
}
