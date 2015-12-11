library atom.debugger_ui;

import 'dart:async';

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

// TODO: have a contributed Flutter section

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

  FocusManager focusManager = new FocusManager();
  // final Property<DebugFrame> currentFrame = new Property();

  StreamSubscriptions subs = new StreamSubscriptions();

  Marker _execMarker;

  FlowControlSection flowControlSection;
  MTabGroup primaryTabGroup;
  MTabGroup secondaryTabGroup;

  final Disposables disposables = new Disposables();

  DebuggerView(this.connection) {
    // Close the debugger view when the launch is collected?

    // Close the debugger view on termination.
    if (connection.isAlive) {
      connection.onTerminated.then((_) {
        _removeExecutionMarker();
        handleClose();
        dispose();
      });
    }

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
    focusManager.focusOn(isolate);
  }

  void _handleIsolateResumed(DebugIsolate isolate) {
    focusManager.handleResumed(isolate);
  }

  void _handleIsolateTerminated(DebugIsolate isolate) {
    if (focusManager.isolate == isolate) {
      // TODO: find the next paused isolate; find any other isolate
      focusManager.focusOn(null);
    }
  }

  // TODO: Shorter title.
  String get label => 'Debug ${connection.launch.name}';

  String get id => viewIdForConnection(connection);

  DebugIsolate get currentIsolate => focusManager.isolate;

  void observeIsolate(callback(DebugIsolate isolate)) {
    focusManager.observeIsolate(callback);
  }

  void dispose() {
    subs.cancel();
    flowControlSection.dispose();
    disposables.dispose();
    _removeExecutionMarker();
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
    if (!existsSync(location.path)) {
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
  final DebugConnection connection;
  final StreamSubscriptions subs = new StreamSubscriptions();

  CoreElement resume;
  CoreElement stepIn;
  CoreElement stepOver;
  CoreElement stepOut;
  CoreElement stop;

  CoreElement subtitle;

  FlowControlSection(this.view, this.connection, CoreElement element) {
    resume = button(c: 'btn icon-playback-play')..click(_resume);
    stepIn = button(c: 'btn icon-jump-down')..click(_stepIn);
    stepOver = button(c: 'btn icon-jump-right')..click(_stepOver);
    stepOut = button(c: 'btn icon-jump-up')..click(_stepOut);
    stop = button(c: 'btn icon-primitive-square')..click(_terminate);

    CoreElement executionControlToolbar = div(c: 'debugger-execution-toolbar')..add([
      resume,
      div()..element.style.width = '1em',
      stepIn,
      stepOver,
      stepOut,
      div()..flex(),
      stop
    ]);

    // TODO: Pull down menu for switching between isolates.
    element.add([
      subtitle = div(
        text: 'no isolate selected',
        c: 'overflow-hidden-ellipsis font-style-italic'
      ),
      executionControlToolbar
    ]);

    view.observeIsolate(_handleIsolateChange);
  }

  void _handleIsolateChange(DebugIsolate isolate) {
    stop.enabled = connection.isAlive;

    if (isolate == null) {
      resume.enabled = false;
      stepIn.enabled = false;
      stepOut.enabled = false;
      stepOver.enabled = false;

      subtitle.text = 'no isolate selected';
      subtitle.toggleClass('font-style-italic', true);

      view._removeExecutionMarker();

      return;
    }

    bool suspended = isolate.suspended;

    resume.enabled = suspended;
    stepIn.enabled = suspended;
    stepOut.enabled = suspended;
    stepOver.enabled = suspended;

    // Update the execution point.
    if (suspended && isolate.hasFrames) {
      // TODO: Do we always want to jump to this tab? Perhaps not when stepping.
      view._showTab('execution');

      // TODO: Select currentFrame instead.
      isolate.frames.first.location.resolve().then((DebugLocation location) {
        view._removeExecutionMarker();

        if (location.resolvedPath) {
          view._jumpToLocation(location, addExecMarker: true);
        }
      });
    } else {
      view._removeExecutionMarker();
    }

    subtitle.toggleClass('font-style-italic', false);
    if (suspended) {
      subtitle.text = 'Isolate ${isolate.name} (paused)';
    } else {
      subtitle.text = 'Isolate ${isolate.name}';
    }
  }

  _resume() => view.currentIsolate?.resume();
  _stepIn() => view.currentIsolate?.stepIn();
  _stepOver() => view.currentIsolate?.stepOver();
  _stepOut() => view.currentIsolate?.stepOut();

  _terminate() => connection.terminate();

  void dispose() => subs.cancel();
}

class ExecutionTab extends MTab {
  final DebuggerView view;
  final DebugConnection connection;
  final StreamSubscriptions subs = new StreamSubscriptions();

  MList<DebugFrame> list;
  MTree<DebugVariable> locals;

  ExecutionTab(this.view, this.connection) : super('execution', 'Execution') {
    content..layoutVertical()..flex();
    content.add([
      list = new MList(_renderFrame)..toggleClass('debugger-frame-area'),
      locals = new MTree(new _LocalTreeModel(), _renderVariable)..flex()
    ]);

    list.selectedItem.onChanged.listen(_selectFrame);
    list.onDoubleClick.listen(_selectFrame);

    view.observeIsolate(_updateFrames);
  }

  void _updateFrames(DebugIsolate isolate) {
    // TODO: When stepping, only remove the frames after a short delay.

    List<DebugFrame> frames = isolate?.frames;
    if (frames == null) frames = [];
    list.update(frames);

    // TODO: Listen to a frame focus manager for this.
    if (frames.isNotEmpty) {
      list.selectItem(frames.first);
    }
  }

  void _renderFrame(DebugFrame frame, CoreElement element) {
    String style = frame.isSystem ? 'icon icon-git-commit' : 'icon icon-three-bars';
    String locationText = getDisplayUri(frame.location.displayPath);
    // String tooltipText = frame.location.displayPath;

    // // TODO: The plan is for the location resolution code to become more synchronous.
    // if (frame.location.line != null) {
    //   tooltipText = '${tooltipText}, '
    //     'line ${frame.location.line}, '
    //     'column ${frame.location.column}';
    // }

    element..add([
      span(c: style),
      span(text: frame.title),
      span(
        text: locationText,
        c: 'debugger-secondary-info overflow-hidden-ellipsis right-aligned'
      )..flex()
    ])..layoutHorizontal();
  }

  void _selectFrame(DebugFrame frame) {
    if (frame == null) {
      locals.update([]);
      return;
    }

    frame.location.resolve().then((DebugLocation location) {
      if (location.resolvedPath) view._jumpToLocation(location);
    });

    List<DebugVariable> vars = frame.locals;
    locals.update(vars ?? []);
  }

  void _renderVariable(DebugVariable local, CoreElement element) {
    // if (local is! DebugVariable) {
    //   print('$local is not a DebugVariable');
    //   print('${local}');
    //   return;
    // }
    //
    // if (local.value is! DebugValue) {
    //   print('${local} value is not a DebugValue');
    //   print('${local.value}');
    //   return;
    // }

    DebugValue value = local.value;
    String valueText;

    if (value == null) {
      valueText = '';
    } else if (value.isString) {
      // We choose not to escape double quotes here; it doesn't work well visually.
      String str = value.valueAsString;
      valueText = value.valueIsTruncated ? '"${str}…' : '"${str}"';
    } else if (value.isList) {
      valueText = 'List [${value.itemsLength}]';
    } else if (value.isMap) {
      valueText = 'Map {${value.itemsLength}}';
    } else if (value.itemsLength != null) {
      valueText = '${value.className} [${value.itemsLength}]';
    } else if (value.isPlainInstance) {
      valueText = '[${value.className}]';
    } else {
      valueText = value.valueAsString;
    }

    element..add([
      span(text: local.name),
      span(
        text: valueText,
        c: 'debugger-secondary-info overflow-hidden-ellipsis right-aligned'
      )..flex()
    ])..layoutHorizontal();
  }

  void dispose() => subs.dispose();
}

class _LocalTreeModel extends TreeModel<DebugVariable> {
  bool canHaveChildren(DebugVariable variable) {
    DebugValue value = variable.value;
    // print(value);
    return !value.isPrimitive;
  }

  Future<List<DebugVariable>> getChildren(DebugVariable obj) {
    return obj.value.getChildren();
  }
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

    view.observeIsolate(_updateLibraries);
  }

  void _updateLibraries(DebugIsolate isolate) {
    if (isolate is ObservatoryIsolate) {
      ObservatoryIsolate obsIsolate = isolate;
      List<ObservatoryLibrary> libraries = obsIsolate.libraries;
      list.update(libraries == null ? [] : libraries);
    } else {
      list.update([]);
    }
  }

  void _render(ObservatoryLibrary lib, CoreElement element) {
    element..add([
      span(text: lib.displayUri, c: 'icon icon-repo'),
      span(
        text: lib.name,
        c: 'debugger-secondary-info overflow-hidden-ellipsis'
      )..flex()
    ])..layoutHorizontal();
  }

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
    view.focusManager.focusOn(isolate);
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

class FocusManager {
  DebugIsolate _isolate;
  List _listeners = [];

  FocusManager();

  DebugIsolate get isolate => _isolate;

  void observeIsolate(callback(DebugIsolate isolate)) {
    callback(isolate);
    _listeners.add(callback);
  }

  void focusOn(DebugIsolate isolate) {
    _isolate = isolate;
    _notifyIsolateListeners();
  }

  void handleResumed(DebugIsolate isolate) {
    if (_isolate == isolate) {
      _notifyIsolateListeners();
    }
  }

  void _notifyIsolateListeners() {
    for (dynamic callback in _listeners) {
      callback(isolate);
    }
  }

  // TODO: frame focus

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
