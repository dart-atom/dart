library atom.usage;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:usage/usage_html.dart';

import 'atom.dart';
import 'atom_utils.dart';
import 'state.dart';
import 'utils.dart';

// Sample Google Analytics UA code.
final String _UA = 'UA-123456-1';

Analytics _ga = new AnalyticsMock();

class UsageManager implements Disposable {
  StreamSubscriptions _subs = new StreamSubscriptions();
  Disposable _editorObserve;

  UsageManager() {
    _init().then((_) => trackCommand('auto-startup'));
  }

  Future _init() {
    return getPackageVersion().then((String version) {
      atom.config.observe('${pluginId}.sendUsage', null, (value) {
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

      analysisServer.isActiveProperty.listen((val) {
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
  int index = path.lastIndexOf('.');
  if (index == -1) {
    _ga.sendScreenView('editor');
  } else {
    path = path.substring(index + 1);
    _ga.sendScreenView('editor/${path.toLowerCase()}');
  }
}

void _handleLogRecord(LogRecord log) {
  if (log.level >= Level.WARNING) {
    bool fatal = log.level >= Level.SEVERE;
    String desc = '${log.loggerName}:${log.message}';
    if (log.error != null) desc += ',${log.error.runtimeType}';
    if (log.stackTrace != null) desc += ',${sanitizeStacktrace(log.stackTrace)}';

    _ga.sendException(desc, fatal: fatal);
  }
}
