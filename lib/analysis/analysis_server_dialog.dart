// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.analysis_server_dialog;

import '../analysis_server.dart';
import '../atom.dart';
import '../elements.dart';
import '../state.dart';
import '../usage.dart' show trackCommand;
import '../utils.dart';

class AnalysisServerDialog implements Disposable {
  final Disposables _disposables = new Disposables();

  TitledModelDialog _dialog;

  CoreElement _messageElement;
  CoreElement _statusElement;
  CoreElement _startButton;
  CoreElement _reanalyzeButton;
  CoreElement _stopButton;

  CoreElement _diagnosticsButton;
  CoreElement _observatoryButton;
  CoreElement _crashDumpButton;

  AnalysisServerDialog() {
    _disposables.add(atom.commands.add('atom-workspace',
        'dartlang:analysis-server-status', (_) => showDialog()));

    analysisServer.onActive.listen((val) => _updateStatus(updateTitle: true));
    analysisServer.onBusy.listen((val) => _updateStatus());
    analysisServer.onSend.listen(_logTraffic);
    analysisServer.onReceive.listen(_logTraffic);
  }

  void dispose() => _disposables.dispose();

  void showDialog() {
    if (_dialog != null) {
      _dialog.show();
      return;
    }

    _dialog = new TitledModelDialog('Analysis Server', classes: 'analysis-dialog');
    _dialog.content.add([
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

    if (AnalysisServer.startWithDebugging) {
      _dialog.content.add(div(c: 'block')..layoutHorizontal()..add([
        _diagnosticsButton = button(text: 'View Diagnostics', c: 'btn btn-sm')..inlineBlockTight(),
        _observatoryButton = button(text: 'Open in Observatory', c: 'btn btn-sm')..inlineBlockTight(),
        div()..inlineBlock()..flex(),
        _crashDumpButton = button(text: 'Download crash dump', c: 'btn btn-sm')..inlineBlockTight()
      ]));

      _diagnosticsButton.click(() => shell.openExternal(AnalysisServer.diagnosticsUrl));
      _observatoryButton.click(() => shell.openExternal(AnalysisServer.observatoryUrl));
      _crashDumpButton.click(() => shell.openExternal('${AnalysisServer.observatoryUrl}_getCrashDump'));
    }

    _updateStatus(updateTitle: true);

    _disposables.add(_dialog);
  }

  void _logTraffic(String message) {
    if (_messageElement != null && _dialog != null) {
      if (message.length > 300) message = '${message.substring(0, 300)}…';
      _messageElement.text = '${message}';
    }
  }

  void _updateStatus({bool updateTitle: false}) {
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

    if (_diagnosticsButton != null) {
      _diagnosticsButton.toggleAttribute('disabled', !analysisServer.isActive);
      _observatoryButton.toggleAttribute('disabled', !analysisServer.isActive);
      _crashDumpButton.toggleAttribute('disabled', !analysisServer.isActive);
    }

    if (updateTitle) {
      if (analysisServer.isActive) {
        analysisServer.server.server.getVersion().then((result) {
          _dialog.title.text = 'Analysis Server (v${result.version})';
        });
      } else {
        _dialog.title.text = 'Analysis Server';
      }
    }
  }

  void _handleServerStart() {
    trackCommand('dartlang:analysis-server-start');
    analysisServer.start();
  }

  void _handleReanalyze() {
    trackCommand('dartlang:reanalyze-sources');
    analysisServer.reanalyzeSources();
  }

  void _handleServerStop() {
    trackCommand('dartlang:analysis-server-stop');
    analysisServer.shutdown();
  }
}
