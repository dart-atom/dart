library atom.debugger_ui2;

import 'package:logging/logging.dart';

import '../atom.dart';
import '../elements.dart';
import '../state.dart';
import '../views.dart';
import 'debugger.dart';
import 'utils.dart';

final Logger _logger = new Logger('atom.debugger_ui2');

// TODO: do something about the outline view - it and the debugger view
// fight for real estate

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

  // MIconButton _stopButton;
  Marker _execMarker;

  DebuggerView(this.connection) {
    // Close the debugger view on termination.
    connection.onTerminated.then((_) {
      handleClose();
      dispose();
    });

    // // Add a stop button to the view toolbar.
    // toolbar.add([
    //   _stopButton = new MIconButton('icon-primitive-square')..tooltip = 'Terminate process'
    // ]);
    // _stopButton.click(_terminate);

    CoreElement titleSection;
    CoreElement primarySection;
    CoreElement secondarySection;

    content..toggleClass('debugger')..toggleClass('tab-non-scrollable')..layoutVertical()..add([
      titleSection = div(c: 'debugger-section view-header'),
      primarySection = div(c: 'debugger-section resizable')..flex(),
      secondarySection = div(c: 'debugger-section resizable debugger-section-last')
    ]);

    _createTitleSection(titleSection);
    _createPrimarySection(primarySection);
    _createSecondarySection(secondarySection);
  }

  void _createTitleSection(CoreElement section) {
    CoreElement title;
    CoreElement subtitle;

    section.add([
      title = div(c: 'view-title'),
      subtitle = div(c: 'view-subtitle')
    ]);

    title.text = 'Debugging ${connection.launch.name}';
    title.tooltip = title.text;

    // TODO:
    subtitle.text = 'Under construction';
  }

  void _createPrimarySection(CoreElement section) {
    section.layoutVertical();

    CoreElement resume = button(c: 'btn icon-playback-play')..click(_resume);
    // CoreElement pause = button(c: 'btn icon-playback-pause')..click(_pause);
    CoreElement stepIn = button(c: 'btn icon-chevron-down')..click(_stepIn);
    CoreElement stepOver = button(c: 'btn icon-chevron-right')..click(_stepOver);
    CoreElement stepOut = button(c: 'btn icon-chevron-up')..click(_stepOut);
    CoreElement stopOut = button(c: 'btn icon-primitive-square')..click(_terminate);

    CoreElement executionControlToolbar = div(c: 'debugger-execution-toolbar')..add([
      resume,
      div()..flex(),
      stepIn,
      stepOver,
      stepOut,
      div()..flex(),
      stopOut
    ]);

    section.add([
      executionControlToolbar,
      // TODO:
      div(c: 'under-construction', text: 'Under construction')..flex()
    ]);

    void updateUi(bool suspended) {
      resume.enabled = suspended;
      // pause.enabled = !suspended;
      stepIn.enabled = suspended;
      stepOut.enabled = suspended;
      stepOver.enabled = suspended;
      stopOut.enabled = connection.isAlive;
      // _stopButton.enabled = connection.isAlive;

      // Update the execution point.
      if (suspended && connection.topFrame != null) {
        connection.topFrame.getLocation().then((DebugLocation location) {
          _removeExecutionMarker();

          if (location != null) {
            _jumpToLocation(location, addExecMarker: true);
          }
        });
      } else {
        _removeExecutionMarker();
      }
    }

    updateUi(connection.isSuspended);
    connection.onSuspendChanged.listen(updateUi);
  }

  void _createSecondarySection(CoreElement section) {
    ViewResizer resizer;

    section.add([
      resizer = new ViewResizer.createHorizontal(),
      // TODO:
      div(c: 'under-construction', text: 'Under construction')..flex()
    ]);

    // TODO: general debugger ui settings
    resizer.position = state['debuggerSplitter'] == null ? 300 : state['debuggerSplitter'];
  }

  // TODO: Shorter title.
  String get label => 'Debug ${connection.launch.name}';

  String get id => viewIdForConnection(connection);

  void dispose() {
    // TODO:

  }

  // TODO: This is temporary.
  // _pause() => connection.pause();
  _resume() => connection.resume();
  _stepIn() => connection.stepIn();
  _stepOver() => connection.stepOver();
  _stepOut() => connection.stepOut();
  _terminate() => connection.terminate();

  void _jumpToLocation(DebugLocation location, {bool addExecMarker: false}) {
    if (statSync(location.path).isFile()) {
      // TODO: Do we also want to adjust the cursor position?
      editorManager.jumpToLocation(location.path).then((TextEditor editor) {
        // Ensure that the execution point is visible.
        editor.scrollToBufferPosition(
            new Point.coords(location.line - 1, location.column - 1), center: true);

        if (addExecMarker) {
          _execMarker?.destroy();

          // Update the execution location markers.
          _execMarker = editor.markBufferRange(
              debuggerCoordsToEditorRange(location.line, location.column),
              persistent: false);

          // The executing line color.
          editor.decorateMarker(_execMarker, {
            'type': 'line', 'class': 'debugger-executionpoint-line'
          });

          // The right-arrow.
          editor.decorateMarker(_execMarker, {
            'type': 'line-number', 'class': 'debugger-executionpoint-linenumber'
          });

          // The column marker.
          editor.decorateMarker(_execMarker, {
            'type': 'highlight', 'class': 'debugger-executionpoint-highlight'
          });
        }
      });
    } else {
      atom.notifications.addWarning("Cannot find file '${location.path}'.");
    }
  }

  void _removeExecutionMarker() {
    if (_execMarker != null) {
      _execMarker.destroy();
      _execMarker = null;
    }
  }
}
