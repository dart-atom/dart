library atom.debugger_ui;

import 'dart:async';
import 'dart:html' show Element, InputElement, MouseEvent;
import 'dart:js' show context, JsFunction;

import 'package:atom/atom.dart';
import 'package:atom/atom_utils.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';
import 'package:logging/logging.dart';

import '../elements.dart';
import '../flutter/flutter_ui.dart';
import '../material.dart';
import '../state.dart';
import '../views.dart';
import 'breakpoints.dart';
import 'debugger.dart';
import 'model.dart';
import 'observatory_debugger.dart';
import 'utils.dart';

final Logger _logger = new Logger('atom.debugger_ui');

// TODO: Ensure that the debugger ui exists over the course of the debug connection,
// and that a new one is not created after a debugger tab is closed, and that
// closing a debugger tab doesn't tear down any listening state.

// TODO: Breakpoints move to its own section.

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
  DetailSection detailSection;
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
    CoreElement flutterElement;
    CoreElement flowControlElement;
    CoreElement primarySection;
    CoreElement detailsElement;
    CoreElement secondarySection;

    root.toggleClass('debugger');

    content..toggleClass('tab-non-scrollable')..layoutVertical()..add([
      titleSection = div(c: 'debugger-section view-header'),
      flutterElement = div(c: 'debugger-section')..hidden(true),
      flowControlElement = div(c: 'debugger-section'),
      primarySection = div(c: 'debugger-section resizable')..layoutVertical()..flex(),
      detailsElement = div(c: 'debugger-section'),
      secondarySection = div(c: 'debugger-section resizable debugger-section-last')
        ..layoutVertical()
    ]);

    _createConfigMenu();

    _createTitleSection(titleSection);
    new FlutterSection(connection, flutterElement);
    _createFlowControlSection(flowControlElement);
    _createPrimarySection(primarySection);
    detailSection = new DetailSection(detailsElement);
    _createSecondarySection(secondarySection);

    subs.add(connection.isolates.onAdded.listen(_handleIsolateAdded));
    subs.add(connection.onPaused.listen(_handleIsolatePaused));
    subs.add(connection.onResumed.listen(_handleIsolateResumed));
    subs.add(connection.isolates.onRemoved.listen(_handleIsolateTerminated));
  }

  void _createConfigMenu() {
    MIconButton button = new MIconButton('icon-gear'); // 'icon-tools'
    button.element.style.position = 'relative';

    CoreElement checkbox;
    InputElement checkElement;

    void _toggleExceptions() {
      breakpointManager.breakOnExceptionType =
        checkElement.checked ? ExceptionBreakType.all : ExceptionBreakType.uncaught;
    };

    CoreElement menu = div(c: 'tooltip bottom dart-inline-dialog')..add([
      div(c: 'tooltip-arrow'),
      div(c: 'tooltip-inner')..add([
        new CoreElement('label')..add([
          checkbox = new CoreElement('input')
            ..setAttribute('type', 'checkbox')
            ..click(_toggleExceptions),
          span(text: 'Break on caught exceptions')
        ])
      ])
    ]);
    menu.element.onClick.listen((MouseEvent e) {
      e.preventDefault();
      e.stopPropagation();
    });
    menu.hidden(true);

    checkElement = checkbox.element;
    checkElement.checked = breakpointManager.breakOnExceptionType != ExceptionBreakType.none;

    subs.add(breakpointManager.onBreakOnExceptionTypeChanged.listen((ExceptionBreakType val) {
      checkElement.checked = breakpointManager.breakOnExceptionType == ExceptionBreakType.all;
    }));

    button
      ..add(menu)
      ..click(() => menu.hidden());
    toolbar.add(button);
  }

  void _createTitleSection(CoreElement section) {
    CoreElement title;

    section.add([
      title = div(c: 'view-title'),
    ]);

    String titleText = connection.launch.targetName ?? connection.launch.name;
    title.text = 'Debugging ${titleText}';
    title.tooltip = title.text;
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
    resizer.position = state['debuggerSplitter'] == null ? 144 : state['debuggerSplitter'];
    resizer.onPositionChanged.listen((pos) => state['debuggerSplitter'] = pos);

    // Set up the tab group.
    // secondaryTabGroup.tabs.add(new EvalTab(this, connection));
    // secondaryTabGroup.tabs.add(new _MockTab('Watchpoints'));
    secondaryTabGroup.tabs.add(new BreakpointsTab());

    disposables.addAll(primaryTabGroup.tabs.items);
    disposables.addAll(secondaryTabGroup.tabs.items);
  }

  void _handleIsolateAdded(DebugIsolate isolate) {
    if (focusManager.isolate == null) {
      focusManager.focusOn(isolate);
    }
  }

  void _handleIsolatePaused(DebugIsolate isolate) {
    focusManager.focusOn(isolate);
  }

  void _handleIsolateResumed(DebugIsolate isolate) {
    focusManager.handleResumed(isolate);
  }

  void _handleIsolateTerminated(DebugIsolate isolate) {
    if (focusManager.isolate == isolate) {
      // Select another isolate.
      DebugIsolate nextFocused = connection.isolates.items.firstWhere((DebugIsolate i) {
        return i != isolate;
      }, orElse: () => null);
      focusManager.focusOn(nextFocused);
    }
  }

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
    if (!fs.existsSync(location.path)) {
      atom.notifications.addWarning("Cannot find file '${location.path}'.");
      return;
    }

    if (!location.resolved) {
      _logger.fine('DebuggerView._jumpToLocation - location is not resolved ($location).');
      return;
    }

    if (location.line == null || location.column == null) {
      editorManager.jumpToLocation(location.path);
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

// class _MockTab extends MTab {
//   _MockTab(String name) : super(name.toLowerCase(), name) {
//     content.toggleClass('under-construction');
//     content.text = '${name}: under construction';
//   }
//
//   void dispose() { }
// }

class FlowControlSection implements Disposable {
  final DebuggerView view;
  final DebugConnection connection;
  final StreamSubscriptions subs = new StreamSubscriptions();

  CoreElement resume;
  CoreElement stepIn;
  CoreElement stepOver;
  CoreElement stepOut;
  CoreElement reload;
  CoreElement stop;

  CoreElement isolateName;
  CoreElement isolateState;

  FlowControlSection(this.view, this.connection, CoreElement element) {
    resume = button(c: 'btn icon-playback-play')..click(_pauseResume)..tooltip = 'Resume';
    stepIn = button(c: 'btn icon-jump-down')..click(_stepIn)..tooltip = 'Step in';
    stepOver = button(c: 'btn icon-jump-right')..click(_autoStepOver)..tooltip = 'Step over';
    stepOut = button(c: 'btn icon-jump-up')..click(_stepOut)..tooltip = 'Step out';
    reload = button(c: 'btn icon-sync')
      ..click(
        _restart,
        () => _restart(fullRestart: true)
      )..tooltip = 'Reload (Shift-click: full reload)';
    stop = button(c: 'btn icon-primitive-square')..click(_terminate)..tooltip = 'Stop';

    CoreElement executionControlToolbar = div(c: 'debugger-execution-toolbar')..add([
      resume,
      div()..element.style.width = '1em',
      stepIn,
      stepOver,
      stepOut,
      div()..flex()
    ]);

    if (connection.launch.supportsRestart) {
      executionControlToolbar.add(reload);
    }
    executionControlToolbar.add(stop);

    // TODO: Pull down menu for switching between isolates.
    element.add([
      div().add([
        isolateName = span(text: 'no isolate selected'),
        isolateState = span(c: 'debugger-secondary-info font-style-italic')
      ]),
      executionControlToolbar
    ]);

    view.observeIsolate(_handleIsolateChange);
  }

  void _handleIsolateChange(DebugIsolate isolate) {
    reload.enabled = connection.isAlive && isolate != null;
    stop.enabled = connection.isAlive;

    if (isolate == null) {
      stepIn.enabled = false;
      stepOut.enabled = false;
      stepOver.enabled = false;

      isolateName.text = 'no isolate selected';

      view._removeExecutionMarker();

      return;
    }

    bool suspended = isolate.suspended;

    resume.toggleClass('icon-playback-pause', !suspended);
    resume.toggleClass('icon-playback-play', suspended);
    resume.tooltip = suspended ? 'Resume' : 'Pause';

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

        if (location.resolved) {
          view._jumpToLocation(location, addExecMarker: true);
        }
      });
    } else {
      view._removeExecutionMarker();
    }

    if (suspended) {
      isolateName.text = 'Isolate ${isolate.displayName}';
      isolateState.text = isolate.hasFrames ? '' : 'paused (no frames)';
    } else {
      isolateName.text = 'Isolate ${isolate.displayName}';
      isolateState.text = 'running';
    }
  }

  _pauseResume() {
    DebugIsolate isolate = view.currentIsolate;
    if (isolate != null) {
      return isolate.suspended ? isolate.resume() : isolate.pause();
    }
  }

  _stepIn() => view.currentIsolate?.stepIn();
  _stepOut() => view.currentIsolate?.stepOut();
  _autoStepOver() => view.currentIsolate?.autoStepOver();

  void _restart({ bool fullRestart: false }) {
    atom.workspace.saveAll();
    connection.launch.restart(fullRestart: fullRestart).catchError((e) {
      atom.notifications.addWarning(e.toString());
    });
  }

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

    locals.selectedItem.onChanged.listen(_showObjectDetails);

    view.observeIsolate(_updateFrames);
  }

  static const Duration _framesDebounceDuration = const Duration(milliseconds: 100);

  Timer _framesClearTimer;

  void _updateFrames(DebugIsolate isolate) {
    _framesClearTimer?.cancel();

    List<DebugFrame> frames = isolate?.frames;

    // When stepping, only change the frames after a short delay.
    _framesClearTimer = new Timer(_framesDebounceDuration, () {
      if (frames == null) frames = [];
      list.update(frames);
      if (frames.isNotEmpty) list.selectItem(frames.first);
    });
  }

  void _renderFrame(DebugFrame frame, CoreElement element) {
    String style = frame.isSystem ? 'icon icon-git-commit' : 'icon icon-three-bars';
    String locationText = getDisplayUri(frame.location.displayPath);

    element..add([
      span(c: style),
      span()..layoutHorizontal()..add([
        span(text: frame.title, c: 'overflow-hidden-ellipsis'),
        span(
          text: locationText,
          c: 'debugger-secondary-info right-aligned overflow-hidden-ellipsis'
        )..flex()
      ])..flex()
    ])..layoutHorizontal();
  }

  void _selectFrame(DebugFrame frame) {
    if (frame == null) {
      locals.update([]);
      return;
    }

    frame.location.resolve().then((DebugLocation location) {
      if (location.resolved) view._jumpToLocation(location);
    });

    List<DebugVariable> vars = frame.locals;
    locals.update(vars ?? []);

    if (frame.isExceptionFrame && vars.isNotEmpty) {
      locals.selectItem(vars.first);
    }
  }

  void _renderVariable(DebugVariable local, CoreElement element) {
    final String valueClass = 'debugger-secondary-info overflow-hidden-ellipsis right-aligned';

    DebugValue value = local.value;

    element.add(span(text: local.name));

    if (value == null) {
      element.add(span(text: '', c: valueClass));
    } else if (value.isString) {
      // We choose not to escape double quotes here; it doesn't work well visually.
      String str = value.valueAsString;
      str = value.valueIsTruncated ? '"${str}…' : '"${str}"';
      element.add(span(text: str, c: valueClass));
    } else if (value.isList) {
      element.add(span(text: '[ ${value.itemsLength} ]', c: valueClass));
    } else if (value.isMap) {
      element.add(span(text: '{ ${value.itemsLength} }', c: valueClass));
    } else if (value.itemsLength != null) {
      element.add(span(text: '${value.className} [ ${value.itemsLength} ]', c: valueClass));
    } else if (value.isPlainInstance) {
      element.add(italic(text: value.className, c: valueClass));
    } else {
      element.add(span(text: value.valueAsString, c: valueClass));
    }

    element.layoutHorizontal();
  }

  void _showObjectDetails(DebugVariable variable) {
    view.detailSection.showDetails(variable);
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

class DetailSection {
  final CoreElement sectionElement;

  CoreElement _detailsElement;

  DetailSection(this.sectionElement) {
    sectionElement..add([
      _detailsElement = div(c: 'debugger-object-details')
    ])..hidden(true);
  }

  void showDetails(DebugVariable variable) {
    if (variable != null) {
      variable.value.invokeToString().then((DebugValue result) {
        String str = result.valueAsString;
        if (result.valueIsTruncated) str += '…';
        _detailsElement.clear();
        _detailsElement.add([
          italic(text: variable.value.className),
          span(text: ': '),
          span(text: str, c: 'text-subtle')
        ]);
        _detailsElement.toggleClass('text-error', false);
      }).catchError((e) {
        _detailsElement.text = '${e}';
        _detailsElement.toggleClass('text-error', true);
      }).whenComplete(() {
        sectionElement.hidden(false);
      });
    } else {
      sectionElement.hidden(true);
    }
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
      span(text: isolate.displayName, c: 'icon icon-versions'),
      span(text: isolate.detail, c: 'debugger-secondary-info overflow-hidden-ellipsis')
    ]);
  }

  void _handleSelectIsolate(DebugIsolate isolate) {
    view.focusManager.focusOn(isolate);
  }

  void dispose() => subs.dispose();
}

// TODO: Finish implementing this; the textfield will not retain event focus.
class EvalTab extends MTab {
  final DebuggerView view;
  final DebugConnection connection;

  final Disposables disposables = new Disposables();

  TextEditor editor;

  EvalTab(this.view, this.connection) : super('eval', 'Eval') {
    CoreElement editorContainer;

    content..add([
      div()..flex(),
      editorContainer = div()
    ])..layoutVertical()..flex();

    editorContainer.element.setInnerHtml(
      '<atom-text-editor mini '
        'data-grammar="source dart" '
        'placeholder-text="evaluate:"></atom-text-editor>',
      treeSanitizer: new TrustedHtmlTreeSanitizer()
    );

    Element editorElement = editorContainer.element.querySelector('atom-text-editor');
    JsFunction editorConverter = context['getTextEditorForElement'];
    editor = new TextEditor(editorConverter.apply([editorElement]));
    editor.setGrammar(atom.grammars.grammarForScopeName('source.dart'));
    editor.selectAll();

    enabled.onChanged.listen((val) {
      // Focus the element.
      if (val) editorElement.focus();
    });

    disposables.add(atom.commands.add(editorElement, 'core:confirm', (_) {
      // TODO:
      print('[${editor.getText()}]');
    }));
  }

  void dispose() => disposables.dispose();
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

  void _update([AtomBreakpoint _]) {
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
      pathText = fs.basename(rel[0]) + ' ' + rel[1];
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
      new MIconButton('icon-dash')..click(handleDelete)..tooltip = "Delete breakpoint"
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
