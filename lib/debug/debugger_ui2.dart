library atom.debugger_ui2;

import 'package:logging/logging.dart';

import '../state.dart';
import '../views.dart';
import 'debugger.dart';

final Logger _logger = new Logger('atom.debugger_ui2');

class DebuggerView extends View {
  static String viewIdForConnection(DebugConnection connection) {
    return 'debug.${connection.hashCode}';
  }

  static DebuggerView showViewForConnection(DebugConnection connection) {
    String id = viewIdForConnection(connection);

    if (viewGroupManager.hasViewId(id)) {
      DebuggerView view = viewGroupManager.getGroup('right').getViewById(id);
      viewGroupManager.activateView(id);
      return view;
    } else {
      DebuggerView view = new DebuggerView(connection);
      viewGroupManager.addView('right', view);
      return view;
    }
  }

  final DebugConnection connection;

  DebuggerView(this.connection) {
    // TODO:
    content.text = 'TODO:';

    connection.onTerminated.then((_) {
      handleClose();
    });
  }

  // TODO: Shorter title.
  String get label => 'Debug ${connection.launch.title}';

  String get id => viewIdForConnection(connection);

  void dispose() {
    // TODO:

  }
}
