library atom.debugger_ui;

import 'package:logging/logging.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../elements.dart';
import '../material.dart';
import '../state.dart';
import '../utils.dart';
import '../views.dart';
import 'breakpoints.dart';
import 'debugger.dart';
import 'model.dart';
import 'utils.dart';

final Logger _logger = new Logger('atom.debugger_ui');

// TODO: do something about the outline view - it and the debugger view
// fight for real estate

// TODO: ensure that the debugger ui exists over the course of the debug connection,
// and that a new one is not created after a debugger tab is closed, and that
// closing a debugger tab doesn't tear down any listening state.

class DebuggerView extends View {
  static String viewIdForConnection(DebugConnection connection) {
    return 'debug.${connection.hashCode}';
  }

  static DebuggerView showViewForConnection(DebugConnection connection) {
    // TODO: also check for any debugger views that were removed from the view
    // group manager but that are still active.

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

  Marker _execMarker;

  MTabGroup primaryTabGroup;
  MTabGroup secondaryTabGroup;

  final Disposables disposables = new Disposables();

  DebuggerView(this.connection) {
    // Close the debugger view on termination.
    connection.onTerminated.then((_) {
      handleClose();
      dispose();
    });

    CoreElement titleSection;
    CoreElement flowControlSection;
    CoreElement primarySection;
    CoreElement secondarySection;

    root.toggleClass('debugger');

    content..toggleClass('tab-non-scrollable')..layoutVertical()..add([
      titleSection = div(c: 'debugger-section view-header'),
      flowControlSection = div(c: 'debugger-section'),
      primarySection = div(c: 'debugger-section resizable')..layoutVertical()..flex(),
      secondarySection = div(c: 'debugger-section resizable debugger-section-last')
        ..layoutVertical()
    ]);

    _createTitleSection(titleSection);
    _createFlowControlSection(flowControlSection);
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

  void _createFlowControlSection(CoreElement section) {
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

    // TODO: Pull down menu for switching between isolates.
    CoreElement subtitle;

    section.add([
      executionControlToolbar,
      subtitle = div(c: 'debugger-section-subtitle', text: ' ')
    ]);

    void updateUi(bool suspended) {
      resume.enabled = suspended;
      // pause.enabled = !suspended;
      stepIn.enabled = suspended;
      stepOut.enabled = suspended;
      stepOver.enabled = suspended;
      stopOut.enabled = connection.isAlive;

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

      if (suspended) {
        subtitle.text = 'Isolate ${connection.isolate.name} (paused)';
      } else {
        if (connection.isolate != null) {
          subtitle.text = 'Isolate ${connection.isolate.name}';
        } else {
          subtitle.text = ' ';
        }
      }
    }

    updateUi(connection.isSuspended);
    connection.onSuspendChanged.listen(updateUi);
  }

  void _createPrimarySection(CoreElement section) {
    section.layoutVertical();


    section.add([
      primaryTabGroup = new MTabGroup()..flex()
    ]);

    // Set up the tab group.
    primaryTabGroup.tabs.add(new ExecutionTab(this, connection));
    primaryTabGroup.tabs.add(new _MockTab('Libraries'));
    primaryTabGroup.tabs.add(new _MockTab('Isolates'));
  }

  void _createSecondarySection(CoreElement section) {
    ViewResizer resizer;

    section.add([
      resizer = new ViewResizer.createHorizontal(),
      secondaryTabGroup = new MTabGroup()..flex()
    ]);

    // Set up the splitter.
    resizer.position = state['debuggerSplitter'] == null ? 225 : state['debuggerSplitter'];
    resizer.onPositionChanged.listen((pos) => state['debuggerSplitter'] = pos);

    // Set up the tab group.
    secondaryTabGroup.tabs.add(new _MockTab('Eval'));
    secondaryTabGroup.tabs.add(new _MockTab('Watchpoints'));
    secondaryTabGroup.tabs.add(new BreakpointsTab());

    disposables.addAll(primaryTabGroup.tabs.items);
    disposables.addAll(secondaryTabGroup.tabs.items);
  }

  // TODO: Shorter title.
  String get label => 'Debug ${connection.launch.name}';

  String get id => viewIdForConnection(connection);

  void dispose() {
    primaryTabGroup.dispose();
    secondaryTabGroup.dispose();
  }

  // TODO: This is temporary.
  // _pause() => connection.pause();
  _resume() => connection.resume();
  _stepIn() => connection.stepIn();
  _stepOver() => connection.stepOver();
  _stepOut() => connection.stepOut();
  _terminate() => connection.terminate();

  void _jumpToLocation(DebugLocation location, {bool addExecMarker: false}) {
    if (!statSync(location.path).isFile()) {
      atom.notifications.addWarning("Cannot find file '${location.path}'.");
      return;
    }

    editorManager.jumpToLocation(location.path, location.line - 1, location.column - 1).then(
        (TextEditor editor) {
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
  }

  void _removeExecutionMarker() {
    if (_execMarker != null) {
      _execMarker.destroy();
      _execMarker = null;
    }
  }
}

class _MockTab extends MTab {
  _MockTab(String name) : super(name.toLowerCase(), name) {
    content.toggleClass('under-construction');
    content.text = '${name}: under construction';

    active.onChanged.listen((val) {
      print(val ? 'activated $this' : 'deactivated $this');
    });
  }

  void dispose() { }
}

class ExecutionTab extends MTab {
  final DebuggerView view;
  final DebugConnection connection;
  MList<DebugFrame> list;
  StreamSubscriptions subs = new StreamSubscriptions();

  ExecutionTab(this.view, this.connection) : super('execution', 'Execution') {
    content..layoutVertical()..flex();
    content.add([
      list = new MList(_render)..flex()
    ]);

    list.selectedItem.onChanged.listen(_selectFrame);
    list.onDoubleClick.listen(_selectFrame);

    if (connection.isSuspended) {
      // TODO: temp
      updateFrames(connection.topFrame == null ? [] : [connection.topFrame]);
    }

    connection.onSuspendChanged.listen((bool suspend) {
      if (suspend) {
        // TODO: temp
        updateFrames(connection.topFrame == null ? [] : [connection.topFrame]);
      } else {
        // TODO: if suspend == false, then remove the frames after a delay

      }
    });
  }

  void updateFrames(List<DebugFrame> frames, {bool selectTop: true}) {
    list.update(frames);

    if (selectTop && frames.isNotEmpty) {
      list.selectItem(frames.first);
    }
  }

  void _render(DebugFrame frame, CoreElement element) {
    // TODO:
    // frame.getLocation() is async!
    // keep it async, but make sure things are efficient?
    // Only resolve the location info when it needs to be displayed?
    String locationText = 'main.dart, line 12:10';

    element..add([
      span(text: frame.title),
      span(
        text: locationText,
        c: 'debugger-secondary-info overflow-hidden-ellipsis right-aligned'
      )..flex()
    ])..layoutHorizontal();
  }

  void _selectFrame(DebugFrame frame) {
    if (frame == null) return;

    frame.getLocation().then((DebugLocation location) {
      if (location != null) view._jumpToLocation(location);
    });
  }

  void dispose() => subs.dispose();
}

class BreakpointsTab extends MTab {
  _TabTitlebar titlebar;
  MList<AtomBreakpoint> list;
  StreamSubscriptions subs = new StreamSubscriptions();

  BreakpointsTab() : super('breakpoints', 'Breakpoints') {
    content..layoutVertical()..flex();

    titlebar = content.add(new _TabTitlebar());

    content.add([
      list = new MList(_render)..flex()
    ]);

    list.onDoubleClick.listen((AtomBreakpoint bp) {
      _openBreakpoint(bp);
    });

    // Set up the list.
    _update();

    // TODO: Support listening for breakpoint change events.
    subs.add(breakpointManager.onAdd.listen(_update));
    subs.add(breakpointManager.onRemove.listen(_update));
  }

  void _update([_]) {
    List<AtomBreakpoint> bps = new List.from(breakpointManager.breakpoints);
    bps.sort();

    if (bps.isEmpty) {
      titlebar.title = 'No breakpoints';
    } else {
      titlebar.title = '${bps.length} ${pluralize('breakpoint', bps.length)}';
    }

    list.update(bps);
  }

  void _render(AtomBreakpoint bp, CoreElement element) {
    String pathText = bp.path;
    List<String> rel = atom.project.relativizePath(bp.path);
    if (rel[0] != null) {
      pathText = basename(rel[0]) + ' ' + rel[1];
    }

    String lineText = 'line ${bp.line}';
    if (bp.column != null) lineText += ':${bp.column}';

    var handleDelete = () {
      breakpointManager.removeBreakpoint(bp);
    };

    element..add([
      span(c: 'icon-primitive-dot debugger-breakpoint-icon'),
      div(c: 'overflow-hidden-ellipsis')..flex()..add([
        span(text: pathText, c: 'debugger-breakpoint-path')..tooltip = bp.path,
        span(text: lineText, c: 'debugger-secondary-info')
      ]),
      new MIconButton('icon-x')..click(handleDelete)
    ])..layoutHorizontal();
  }

  void _openBreakpoint(AtomBreakpoint bp) {
    int col = bp.column == null ? null : bp.column - 1;
    editorManager.jumpToLocation(bp.path, bp.line - 1, col);
  }

  void dispose() => subs.dispose();
}

class _TabTitlebar extends CoreElement {
  CoreElement titleElement;
  CoreElement toolbar;

  _TabTitlebar() : super('div', classes: 'debug-tab-container') {
    layoutHorizontal();

    add([
      titleElement = div(c: 'debug-tab-title')..flex(),
      toolbar = div(c: 'debug-tab-toolbar')
    ]);
  }

  set title(String value) {
    titleElement.text = value;
  }
}
