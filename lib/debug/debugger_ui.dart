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
import 'observatory_debugger.dart';
import 'utils.dart';

final Logger _logger = new Logger('atom.debugger_ui');

// TODO: do something about the outline view - it and the debugger view
// fight for real estate

// TODO: ensure that the debugger ui exists over the course of the debug connection,
// and that a new one is not created after a debugger tab is closed, and that
// closing a debugger tab doesn't tear down any listening state.

// TODO: current connection (can be null)

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

  final Property<DebugIsolate> currentIsolate = new Property();
  final Property<DebugFrame> currentFrame = new Property();

  StreamSubscriptions subs = new StreamSubscriptions();

  Marker _execMarker;

  FlowControlSection flowControlSection;
  MTabGroup primaryTabGroup;
  MTabGroup secondaryTabGroup;

  final Disposables disposables = new Disposables();

  DebuggerView(this.connection) {
    // Close the debugger view on termination.
    connection.onTerminated.then((_) {
      _removeExecutionMarker();
      handleClose();
      dispose();
    });

    CoreElement titleSection;
    CoreElement flowControlElement;
    CoreElement primarySection;
    CoreElement secondarySection;

    root.toggleClass('debugger');

    content..toggleClass('tab-non-scrollable')..layoutVertical()..add([
      titleSection = div(c: 'debugger-section view-header'),
      flowControlElement = div(c: 'debugger-section'),
      primarySection = div(c: 'debugger-section resizable')..layoutVertical()..flex(),
      secondarySection = div(c: 'debugger-section resizable debugger-section-last')
        ..layoutVertical()
    ]);

    _createTitleSection(titleSection);
    _createFlowControlSection(flowControlElement);
    _createPrimarySection(primarySection);
    _createSecondarySection(secondarySection);

    subs.add(connection.onPaused.listen(_handleIsolatePaused));
    subs.add(connection.onResumed.listen(_handleIsolateResumed));
    subs.add(connection.isolates.onRemoved.listen(_handleIsolateTerminated));

    // currentIsolate.observe((DebugIsolate isolate) {
    //   print('current isolate: ${isolate}');
    // });
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

    subs.add(connection.metadata.observe((val) {
      subtitle.text = val == null ? ' ' : val;
      subtitle.tooltip = subtitle.text;
    }));
  }

  void _createFlowControlSection(CoreElement section) {
    flowControlSection = new FlowControlSection(this, connection, section);
  }

  void _createPrimarySection(CoreElement section) {
    section.layoutVertical();

    section.add([
      primaryTabGroup = new MTabGroup()..flex()
    ]);

    // Set up the tab group.
    primaryTabGroup.tabs.add(new ExecutionTab(this, connection));
    primaryTabGroup.tabs.add(new LibrariesTab(this, connection));
    primaryTabGroup.tabs.add(new IsolatesTab(this, connection));
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

  void _handleIsolatePaused(DebugIsolate isolate) {
    currentIsolate.value = isolate;
  }

  void _handleIsolateResumed(DebugIsolate isolate) {
    // TODO: Instead of this, invoke registered callbacks.
    currentIsolate.value = isolate;
  }

  void _handleIsolateTerminated(DebugIsolate isolate) {
    if (currentIsolate.value == isolate) {
      // TODO: find the next paused isolate; find any other isolate
      currentIsolate.value = null;
    }
  }

  // TODO: Shorter title.
  String get label => 'Debug ${connection.launch.name}';

  String get id => viewIdForConnection(connection);

  void dispose() {
    subs.cancel();
    flowControlSection.dispose();
    disposables.dispose();
  }

  void _showTab(String id) {
    if (primaryTabGroup.hasTabId(id)) {
      primaryTabGroup.activateTabId(id);
    }
    if (secondaryTabGroup.hasTabId(id)) {
      secondaryTabGroup.activateTabId(id);
    }
  }

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
  }

  void dispose() { }
}

class FlowControlSection implements Disposable {
  final DebuggerView view;
  final ObservatoryConnection connection;
  final StreamSubscriptions subs = new StreamSubscriptions();

  CoreElement resume;
  CoreElement stepIn;
  CoreElement stepOver;
  CoreElement stepOut;
  CoreElement stop;

  CoreElement subtitle;

  DebugIsolate _isolate;

  FlowControlSection(this.view, this.connection, CoreElement element) {
    resume = button(c: 'btn icon-playback-play')..click(_resume);
    stepIn = button(c: 'btn icon-chevron-down')..click(_stepIn);
    stepOver = button(c: 'btn icon-chevron-right')..click(_stepOver);
    stepOut = button(c: 'btn icon-chevron-up')..click(_stepOut);
    stop = button(c: 'btn icon-primitive-square')..click(_terminate);

    CoreElement executionControlToolbar = div(c: 'debugger-execution-toolbar')..add([
      resume,
      div()..flex(),
      stepIn,
      stepOver,
      stepOut,
      div()..flex(),
      stop
    ]);

    // TODO: Pull down menu for switching between isolates.
    element.add([
      executionControlToolbar,
      subtitle = div(c: 'debugger-section-subtitle', text: ' ')
    ]);

    view.currentIsolate.observe(_handleIsolateChange);
  }

  void _handleIsolateChange(DebugIsolate isolate) {
    // The current isolate has changed.
    _isolate = isolate;

    _updateUI();
  }

  void _updateUI() {
    stop.enabled = connection.isAlive;

    if (_isolate == null) {
      resume.enabled = false;
      stepIn.enabled = false;
      stepOut.enabled = false;
      stepOver.enabled = false;

      subtitle.text = ' ';
      view._removeExecutionMarker();

      return;
    }

    bool suspended = _isolate.isSuspended;

    resume.enabled = suspended;
    stepIn.enabled = suspended;
    stepOut.enabled = suspended;
    stepOver.enabled = suspended;

    // Update the execution point.
    if (suspended && _isolate.hasFrames) {
      // TODO: Do we always want to jump to this tab? Perhaps not when stepping.
      view._showTab('execution');

      // TODO: Select currentFrame instead.
      _isolate.frames.first.location.resolve().then((DebugLocation location) {
        view._removeExecutionMarker();

        if (location.resolvedPath) {
          view._jumpToLocation(location, addExecMarker: true);
        }
      });
    } else {
      view._removeExecutionMarker();
    }

    if (suspended) {
      subtitle.text = 'Isolate ${_isolate.name} (paused)';
    } else {
      subtitle.text = 'Isolate ${_isolate.name}';
    }
  }

  _resume() => _isolate?.resume();
  _stepIn() => _isolate?.stepIn();
  _stepOver() => _isolate?.stepOver();
  _stepOut() => _isolate?.stepOut();

  _terminate() => connection.terminate();

  void dispose() => subs.cancel();
}

class ExecutionTab extends MTab {
  final DebuggerView view;
  final DebugConnection connection;
  final StreamSubscriptions subs = new StreamSubscriptions();

  MList<DebugFrame> list;

  ExecutionTab(this.view, this.connection) : super('execution', 'Execution') {
    content..layoutVertical()..flex();
    content.add([
      list = new MList(_render)..flex()
    ]);

    list.selectedItem.onChanged.listen(_selectFrame);
    list.onDoubleClick.listen(_selectFrame);

    // if (connection.isolate.suspended.value) {
    //   updateFrames(connection.isolate.frames);
    // }
    //
    // connection.isolate.suspended.onChanged.listen((bool suspend) {
    //   if (suspend) {
    //     updateFrames(connection.isolate.frames);
    //   } else {
    //     // TODO: if suspend == false, then remove the frames after a delay
    //
    //   }
    // });

    // ***
    // TODO: add a util method in view, observeIsolateState
    // ***

    // TODO: Listen to currentIsolate.
    view.currentIsolate.observe(_updateFrames);
  }

  void _updateFrames(DebugIsolate isolate, {bool selectTop: true}) {
    List<DebugFrame> frames = isolate?.frames;
    if (frames == null) frames = [];
    list.update(frames);

    if (selectTop && frames.isNotEmpty) {
      list.selectItem(frames.first);
    }
  }

  void _render(DebugFrame frame, CoreElement element) {
    // TODO:
    String locationText = _displayUri(frame.location.displayPath);

    // TODO: when the location resolves, update the icon?

    element..add([
      span(text: frame.title, c: 'icon icon-code'),
      span(
        text: locationText,
        c: 'debugger-secondary-info overflow-hidden-ellipsis right-aligned'
      )..flex()
    ])..layoutHorizontal();
  }

  void _selectFrame(DebugFrame frame) {
    if (frame == null) return;

    frame.location.resolve().then((DebugLocation location) {
      if (location.resolvedPath) view._jumpToLocation(location);
    });
  }

  void dispose() => subs.dispose();
}

// TODO: Show (expandable) library properties as well.
class LibrariesTab extends MTab {
  final DebuggerView view;
  final DebugConnection connection;
  MList<ObservatoryLibrary> list;

  LibrariesTab(this.view, this.connection) : super('libraries', 'Libraries') {
    content..layoutVertical()..flex();
    content.add([
      list = new MList(
        _render,
        sort: _sort,
        filter: _filter
      )..flex()
    ]);

    // TODO: On double click, jump to the library source.
    // list.onDoubleClick.listen(_selectIsolate);

    view.currentIsolate.observe(_updateLibraries);
  }

  void _updateLibraries([_]) {
    if (view.currentIsolate.value is ObservatoryIsolate) {
      ObservatoryIsolate obsIsolate = view.currentIsolate.value;
      List<ObservatoryLibrary> libraries = obsIsolate.libraries;
      list.update(libraries == null ? [] : libraries);
    } else {
      list.update([]);
    }
  }

  void _render(ObservatoryLibrary lib, CoreElement element) {
    element..add([
      span(text: lib.name, c: 'icon icon-repo'),
      span(
        text: _displayUri(lib.uri),
        c: 'debugger-secondary-info overflow-hidden-ellipsis'
      )..flex()
    ])..layoutHorizontal();
  }

  // TODO: sort by short uri name
  int _sort(ObservatoryLibrary a, ObservatoryLibrary b) => a.compareTo(b);

  bool _filter(ObservatoryLibrary lib) => lib.private;

  void dispose() { }
}

class IsolatesTab extends MTab {
  final DebuggerView view;
  final DebugConnection connection;

  MList<DebugIsolate> list;
  StreamSubscriptions subs = new StreamSubscriptions();

  IsolatesTab(this.view, this.connection) : super('isolates', 'Isolates') {
    content..layoutVertical()..flex();
    content.add([
      list = new MList(_render)..flex()
    ]);

    list.onDoubleClick.listen(_handleSelectIsolate);

    subs.add(connection.isolates.observeMutation((_) => _updateIsolates()));
  }

  void _updateIsolates() {
    list.update(connection.isolates.items);
  }

  void _render(DebugIsolate isolate, CoreElement element) {
    // TODO: pause button, pause state
    element..add([
      span(text: isolate.name, c: 'icon icon-versions'),
      span(text: isolate.detail, c: 'debugger-secondary-info overflow-hidden-ellipsis')
    ]);
  }

  void _handleSelectIsolate(DebugIsolate isolate) {
    // TODO: Not all parts of the UI listen to currentIsolate.
    // view.currentIsolate.value = isolate;
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

    // TODO: Support listening for breakpoint property change events.

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

String _displayUri(String uri) {
  if (uri == null) return null;

  if (uri.startsWith('file:')) {
    String path = Uri.parse(uri).toFilePath();
    return atom.project.relativizePath(path)[1];
  }

  return uri;
}
