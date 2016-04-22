library atom.usage;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/package.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';
import 'package:usage/usage_html.dart';

import 'projects.dart';
import 'state.dart';

final String _UA = 'UA-26406144-22';

Analytics _ga = new AnalyticsMock();

class UsageManager implements Disposable {
  StreamSubscriptions _subs = new StreamSubscriptions();
  Disposable _editorObserve;

  UsageManager() {
    _init().then((_) => trackCommand('auto-startup'));
  }

  Future _init() {
    return atomPackage.getPackageVersion().then((String version) {
      atom.config.observe('${pluginId}.sendUsage', null, (value) {
        // Disable Google Analytics if the UA is the placeholder one.
        if (_UA.startsWith('UA-0000')) value = false;

        if (value == true) {
          _ga = new AnalyticsHtml(_UA, pluginId, version);
          _ga.optIn = true;
          _ga.sendScreenView('editor');
        } else {
          _ga = new AnalyticsMock();
        }
      });

      _subs.add(Logger.root.onRecord.listen(_handleLogRecord));
      _subs.add(atom.commands.onDidDispatch.listen(trackCommand));

      _editorObserve = atom.workspace.observeActivePaneItem(_activePaneItemChanged);

      analysisServer.onActive.listen((val) {
        trackCommand(val ? 'auto-analysis-server-start' : 'auto-analysis-server-stop');
      });
    });
  }

  void dispose() {
    trackCommand('auto-shutdown');
    _subs.cancel();
    if (_editorObserve != null) _editorObserve.dispose();
  }
}

void trackCommand(String command) {
  String category = 'dartlang';

  List list = command.split(':');
  if (list.length >= 2) {
    category = list[0];
    command = list[1];
  }

  // Ignore `core:` commands (core:confirm, core:cancel, ...).
  if (category == 'core') return;

  // Ignore `dartlang:newline`.
  if (command == 'newline') return;

  _ga.sendEvent(category, command);
}

void _activePaneItemChanged(_) {
  TextEditor editor = atom.workspace.getActiveTextEditor();
  if (editor == null || editor.getPath() == null) return;

  String path = editor.getPath();

  // Ensure that the file is Dart related.
  if (isDartFile(path) || projectManager.getProjectFor(path) != null) {
    int index = path.lastIndexOf('.');
    if (index == -1) {
      _ga.sendScreenView('editor');
    } else {
      String extension = path.substring(index + 1);
      _ga.sendScreenView('editor/${extension.toLowerCase()}');
    }
  }
}

void _handleLogRecord(LogRecord log) {
  if (log.level >= Level.WARNING) {
    bool fatal = log.level >= Level.SEVERE;
    String message = log.message;
    if (message.contains('/Users/')) {
      message = message.substring(0, message.indexOf('/Users/'));
    }
    String desc = '${log.loggerName}:${message}';
    if (log.error != null) desc += ',${log.error.runtimeType}';
    if (log.stackTrace != null) desc += ',${sanitizeStacktrace(log.stackTrace)}';
    _ga.sendException(desc, fatal: fatal);
  }
}
