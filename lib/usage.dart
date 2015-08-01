library atom.usage;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:usage/usage_html.dart';

import 'atom.dart';
import 'atom_utils.dart';
import 'state.dart';

// TODO: Convert warning and severe logging calls over to using exception + st.

Analytics _ga = new AnalyticsMock();

// TODO: !!!
final String _UA = 'UA-55029513-1';

Future init() {
  return getPackageVersion().then((String version) {
    atom.config.observe('${pluginId}.sendUsageInformation', null, (value) {
      if (value) {
        _ga = new AnalyticsHtml(_UA, pluginId, version);
        _ga.optIn = true;
        _init();
      } else {
        _ga = new AnalyticsMock();
        _init();
      }
    });

    Logger.root.onRecord.listen(_handleLogRecord);

    analysisServer.isActiveProperty.listen((val) {
      trackCommand(val ? 'auto-analysis-server-start' : 'auto-analysis-server-stop');
    });
  });
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

void _init() {
  commandWatcher = (String command, AtomEvent event) {
    trackCommand(command);
  };

  _ga.sendScreenView('editor');
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
