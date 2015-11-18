/// A library for a general view implementation in Atom.
library atom.views;

import 'dart:async';
import 'dart:html';
import 'dart:math' as math;

import 'atom.dart' hide Point;
import 'dependencies.dart';
import 'elements.dart';
import 'state.dart';
import 'utils.dart';

class ViewResizer extends CoreElement {
  StreamController<num> _controller = new StreamController.broadcast();

  Point<num> _offset = new Point(0, 0);

  StreamSubscription _moveSub;
  StreamSubscription _upSub;

  ViewResizer.createHorizontal() : super('div') {
    horizontalSplitter = true;
    _init();
  }

  ViewResizer.createVertical() : super('div') {
    verticalSplitter = true;
    _init();
  }

  bool get horizontalSplitter => hasAttribute('horizontal');
  set horizontalSplitter(bool value) {
    clearAttribute(value ? 'vertical' : 'horizontal');
    attribute(value ? 'horizontal' : 'vertical');
  }

  bool get verticalSplitter => hasAttribute('vertical');
  set verticalSplitter(bool value) {
    clearAttribute(value ? 'horizontal' : 'vertical');
    attribute(value ? 'vertical' : 'horizontal');
  }

  num get position => _targetSize;

  set position(num value) {
    _targetSize = value;
  }

  Stream<num> get onPositionChanged => _controller.stream;

  void _init() {
    element.classes.toggle('view-resize', true);
    if (!horizontalSplitter && !verticalSplitter) horizontalSplitter = true;

    var cancel = () {
      if (_moveSub != null) _moveSub.cancel();
      if (_upSub != null) _upSub.cancel();
    };

    element.onMouseDown.listen((e) {
      if (e.which != 1) return;

      e.preventDefault();
      _offset = e.offset as Point<num>;

      _moveSub = document.onMouseMove.listen((MouseEvent e) {
        if (e.which != 1) {
          cancel();
        } else {
          Point<num> current =
              _target.marginEdge.bottomRight - (e.client  as Point<num>) + _offset;
          _handleDrag(current);
        }
      });

      _upSub = document.onMouseUp.listen((e) {
        cancel();
      });
    });
  }

  void _handleDrag(Point size) {
    final num currentPos = _controller.hasListener ? position : null;

    _targetSize = verticalSplitter ? size.x : size.y;

    if (_controller.hasListener) {
      num newPos = position;
      if (currentPos != newPos) _controller.add(newPos);
    }
  }

  Element get _target => element.parent;

  num _minSize(Element e) {
    CssStyleDeclaration style = e.getComputedStyle();
    String str = verticalSplitter ? style.minWidth : style.minHeight;
    if (str.isEmpty) return 0;
    if (str.endsWith('px')) str = str.substring(0, str.length - 2);
    return num.parse(str, (_) => 0);
  }

  num get _targetSize {
    CssStyleDeclaration style = _target.getComputedStyle();
    String str = verticalSplitter ? style.width : style.height;
    if (str.endsWith('px')) str = str.substring(0, str.length - 2);
    return num.parse(str, (_) => 0);
  }

  set _targetSize(num size) {
    size = math.max(size, _minSize(element));

    if (verticalSplitter) {
      _target.style.width = '${size}px';
    } else {
      _target.style.height = '${size}px';
    }
  }
}

class AtomView implements Disposable  {
  static const int _defaultWidth = 250;
  static const int _defaultHeight = 125;

  static ViewGroupManager get groupManager {
    if (deps[ViewGroupManager] == null) deps[ViewGroupManager] = new ViewGroupManager();
    return deps[ViewGroupManager];
  }

  final String groupName;

  Panel _panel;
  String _id;
  Disposables disposables = new Disposables();
  StreamSubscriptions subs = new StreamSubscriptions();

  CoreElement root;
  CoreElement title;
  CoreElement content;

  AtomView(String inTitle, {String classes, String prefName,
      bool rightPanel: true, bool cancelCloses: true, bool showTitle: true,
      this.groupName}) {
    _id = toStartingLowerCase(inTitle);

    CoreElement closeButton;
    ViewResizer resizer;

    String c = 'atom-view tree-view';
    if (classes != null) c = '${c} ${classes}';

    root = div(c: c)..layoutVertical();

    if (showTitle) {
      root.add(
        div(c: 'view-header panel-heading')..layoutHorizontal()..add([
          title = div(text: inTitle, c: 'text-highlight')..flex(),
          closeButton = new CloseButton()
        ])
      );
      closeButton.onClick.listen((e) {
        hide();
        e.preventDefault();
      });
    }

    root.add([
      content = div(c: 'view-content')..flex(),
      resizer = rightPanel
          ? new ViewResizer.createVertical() : new ViewResizer.createHorizontal()
    ]);

    if (prefName == null && groupName != null) prefName = groupName;
    _setupResizer(prefName, resizer, rightPanel ? _defaultWidth : _defaultHeight);

    if (rightPanel) {
      _panel = atom.workspace.addRightPanel(item: root.element, visible: false);
    } else {
      _panel = atom.workspace.addBottomPanel(item: root.element, visible: false);
    }

    if (cancelCloses) {
      disposables.add(
        atom.commands.add('atom-workspace', 'core:cancel', (_) => _handleCancel()));
    }

    if (groupName != null) {
      groupManager.addView(groupName, this);
    }
  }

  String get id => _id;

  void _setupResizer(String prefName, ViewResizer resizer, int defaultSize) {
    if (prefName == null) {
      resizer.position = defaultSize;
    } else {
      resizer.position = state[prefName] == null ? defaultSize : state[prefName];

      bool _amChanging = false;

      subs.add(state.onValueChanged(prefName).listen((val) {
        if (!_amChanging) resizer.position = val;
      }));

      resizer.onPositionChanged.listen((pos) {
        _amChanging = true;
        state[prefName] = pos;
        _amChanging = false;
      });
    }
  }

  Timer _timer;

  void _handleCancel() {
    // Double tap escape to close.
    if (_timer != null) {
      hide();
    } else {
      _timer = new Timer(new Duration(milliseconds: 750), () => _timer = null);
    }
  }

  bool isVisible() => _panel.isVisible();

  void toggle() => isVisible() ? hide() : show();

  void show() {
    _panel.show();
    groupManager.viewShowing(groupName, this);
  }

  void hide() => _panel.hide();

  void dispose() {
    groupManager.removeView(groupName, this);
    _panel.invoke('destroy');
    disposables.dispose();
    subs.cancel();
  }
}

class ViewGroupManager {
  Map<String, ViewGroup> _groups = {};

  ViewGroupManager();

  ViewGroup getGroup(String name) => _groups[name];

  void addView(String name, AtomView view) {
    if (!_groups.containsKey(name)) _groups[name] = new ViewGroup(name);
    _groups[name].addView(view);
  }

  /// Returns the name of the previously visible view.
  String viewShowing(String name, AtomView view) {
    if (_groups.containsKey(name)) {
      return _groups[name].viewShowing(view);
    } else {
      return null;
    }
  }

  void removeView(String name, AtomView view) {
    if (_groups.containsKey(name)) {
      _groups[name].removeView(view);
    }
  }

  void showView(String groupName, String viewId) {
    if (_groups.containsKey(groupName)) {
      _groups[groupName].showView(viewId);
    }
  }
}

class ViewGroup {
  final String name;
  final List<AtomView> views = [];
  String _currentVisible;

  ViewGroup(this.name);

  void addView(AtomView view) {
    views.add(view);
  }

  /// Returns the name of the previously visible view.
  String viewShowing(AtomView view) {
    String lastVisible = _currentVisible;
    _currentVisible = view?.id;
    for (AtomView v in views) {
      if (v != view) {
        if (v.isVisible()) v.hide();
      }
    }
    return lastVisible;
  }

  void removeView(AtomView view) {
    if (_currentVisible == view?.id) _currentVisible = null;
    views.remove(view);
  }

  void showView(String viewId) {
    for (AtomView view in views) {
      if (view.id == viewId) {
        if (!view.isVisible()) view.show();
        return;
      }
    }
  }
}

// TODO: remove old view framework

// TODO: convert console views

class ViewGroupManager2 implements Disposable {
  Map<String, ViewGroup2> _groups = {};

  ViewGroupManager2();

  ViewGroup2 getGroup(String name) => _groups[name];

  void addView(String groupName, View2 view, {bool activate: true}) {
    if (!_groups.containsKey(groupName)) {
      _groups[groupName] = new ViewGroup2(groupName);
    }
    _groups[groupName].addView(view, activate: activate);
  }

  void activateView(String viewId) {
    for (ViewGroup2 group in _groups.values) {
      if (group.hasViewId(viewId)) {
        group.activateViewById(viewId);
      }
    }
  }

  void activate(View2 view) {
    for (ViewGroup2 group in _groups.values) {
      if (group.hasView(view)) {
        group.activateView(view);
      }
    }
  }

  bool isActiveId(String viewId) {
    return _groups.values.any((group) => group.isActiveId(viewId));
  }

  bool hasViewId(String viewId) {
    return _groups.values.any((group) => group.hasViewId(viewId));
  }

  void dispose() {
    for (ViewGroup2 group in _groups.values.toList()) {
      group.dispose();
    }
  }

  void removeViewId(String id) {
    for (ViewGroup2 group in _groups.values) {
      if (group.hasViewId(id)) {
        group.removeView(group.getViewById(id));
      }
    }
  }
}

class ViewGroup2 implements Disposable {
  static const int _defaultWidth = 250;
  static const int _defaultHeight = 125;

  final String name;
  final SelectionGroup<View2> views = new SelectionGroup();

  CoreElement root;
  CoreElement tabHeader;
  CoreElement content;

  CloseButton _closeButton;
  Panel _panel;

  View2 _active;
  List<View2> _history = [];

  ViewGroup2(this.name) {
    bool rightPanel = name == 'right';

    String c = 'atom-view tree-view';
    root = div(c: c)..layoutVertical();
    ViewResizer resizer;

    root.add([
      tabHeader = ul(c: 'list-inline tab-bar inset-panel')..hidden(),
      content = div(c: 'view-content')..flex(),
      _closeButton = new CloseButton(),
      resizer = rightPanel
          ? new ViewResizer.createVertical() : new ViewResizer.createHorizontal()
    ]);

    _closeButton.hidden();
    _closeButton.click(() => views.selection.handleClose());
    _closeButton.element.style
      ..position = 'absolute'
      ..right = '8px'
      ..top = '6px';

    if (rightPanel) {
      _panel = atom.workspace.addRightPanel(item: root.element, visible: false);
    } else {
      _panel = atom.workspace.addBottomPanel(item: root.element, visible: false);
    }

    _setupResizer(
      '${name}Panel', resizer, rightPanel ? _defaultWidth : _defaultHeight);

    views.onAdded.listen(_onViewAdded);
    views.onSelectionChanged.listen(_onActiveChanged);
    views.onRemoved.listen(_onViewRemoved);
  }

  bool get hidden => !showing;
  bool get showing => _panel.isVisible();

  void addView(View2 view, {bool activate: true}) {
    view.group = this;

    view.handleDeactivate();
    content.add(view.element);
    views.add(view);
    if (views.length > 1 && activate) views.setSelection(view);
  }

  bool hasViewId(String viewId) => getViewById(viewId) != null;

  bool hasView(View2 view) => views.items.contains(view);

  View2 getViewById(String viewId) {
    return views.items.firstWhere((view) => view.id == viewId, orElse: () => null);
  }

  void activateViewById(String viewId) {
    View2 view = getViewById(viewId);
    if (view != null) views.setSelection(view);
  }

  void activateView(View2 view) {
    views.setSelection(view);
  }

  bool isActiveId(String viewId) {
    return _active != null ? _active.id == viewId : false;
  }

  void removeView(View2 view) {
    if (view != null) views.remove(view);
  }

  void _onViewAdded(View2 view) {
    if (hidden && views.items.isNotEmpty) _setVisible(true);
    tabHeader.hidden(views.length < 2);
    _closeButton.hidden(views.length != 1);
    tabHeader.add(view.tabElement);
  }

  void _onActiveChanged(View2 view) {
    _active?.handleDeactivate();
    _active = view;
    _active?.handleActivate();

    if (_active != null) {
      _history.remove(_active);
      _history.add(_active);
    }

    if (_active == null && _history.isNotEmpty) {
      views.setSelection(_history.last);
    }
  }

  void _onViewRemoved(View2 view) {
    _history.remove(view);
    if (showing && views.items.isEmpty) _setVisible(false);
    tabHeader.hidden(views.length < 2);
    _closeButton.hidden(views.length != 1);
    view.element.dispose();
    view.tabElement.dispose();
    view.dispose();
  }

  void _setVisible(bool value) {
    value ? _panel.show() : _panel.hide();
  }

  void _setupResizer(String prefName, ViewResizer resizer, int defaultSize) {
    resizer.position = state[prefName] == null ? defaultSize : state[prefName];
    resizer.onPositionChanged.listen((pos) => state[prefName] = pos);
  }

  void dispose() {
    _panel.destroy();

    for (View2 view in views.items) {
      view.dispose();
    }
  }
}

abstract class View2 implements Disposable {
  CoreElement tabElement;
  ViewGroup2 group;

  View2() {
    tabElement = li(c: 'tab')..add([
      div(text: label, c: 'title')..click(_handleTab),
      div(c: 'close-icon')..click(handleClose)
    ]);
  }

  String get id;
  String get label;
  CoreElement get element;

  void dispose();

  void handleActivate() {
    element.toggleAttribute('hidden', false);
    tabElement.toggleClass('active', true);
  }

  void handleDeactivate() {
    element.toggleAttribute('hidden', true);
    tabElement.toggleClass('active', false);
  }

  void _handleTab() {
    group.activateView(this);
  }

  void handleClose() {
    group.removeView(this);
  }

  String toString() => '[${label} ${id}]';
}

class ListTreeBuilder extends CoreElement {
  final StreamController<Node> _clickController = new StreamController.broadcast();
  final StreamController<Node> _doubleClickController = new StreamController.broadcast();
  final Function render;

  final bool hasToggle;

  List<Node> nodes = [];

  List<Node> _selectedNodes = [];
  Map<Node, Element> _nodeToElementMap = {};

  String _selectionClass = 'tree-selected';

  ListTreeBuilder(this.render, {this.hasToggle: true}) :
      super('div', classes: 'list-tree has-collapsable-children');

  void setSelectionClass(String className) {
    _selectionClass = className;
  }

  Node get selectedNode => _selectedNodes.isEmpty ? null : _selectedNodes.first;

  void addNode(Node node) => _addNode(this, node);

  void _addNode(CoreElement parent, Node node) {
    nodes.add(node);

    if (!node.canHaveChildren) {
      CoreElement element = li(c: 'list-item');
      Element e = element.element;
      render(node.data, e);
      _nodeToElementMap[node] = e;
      e.onClick.listen((_) => _clickController.add(node));
      e.onDoubleClick.listen((_) => _doubleClickController.add(node));
      parent.add(element);
    } else {
      CoreElement element = li(c: 'list-nested-item');
      parent.add(element);

      CoreElement d = div(c: 'list-item');
      Element e = d.element;
      render(node.data, e);
      _nodeToElementMap[node] = e;
      e.onClick.listen((_) => _clickController.add(node));
      e.onDoubleClick.listen((Event event) {
        if (!event.defaultPrevented) _doubleClickController.add(node);
      });
      element.add(d);

      CoreElement u = ul(c: 'list-tree');
      element.add(u);

      if (hasToggle) {
        e.onClick.listen((MouseEvent e) {
          // Only respond to clicks on the toggle arrow.
          if (e.offset.x < 12) {
            element.toggleClass('collapsed');
            e.preventDefault();
            e.stopPropagation();
          }
        });
      }

      for (Node child in node.children) {
        _addNode(u, child);
      }
    }
  }

  void selectNode(Node node) {
    selectNodes(node == null ? [] : [node]);
  }

  void selectNodes(List<Node> selected) {
    // .selected uses absolute positioning...
    if (_selectedNodes.isNotEmpty) {
      for (Node n in _selectedNodes) {
        Element e = _nodeToElementMap[n];
        if (e != null) e.classes.toggle(_selectionClass, false);
      }
    }

    _selectedNodes.clear();
    _selectedNodes.addAll(selected);

    if (_selectedNodes.isNotEmpty) {
      for (Node n in _selectedNodes) {
        Element e = _nodeToElementMap[n];
        if (e != null) e.classes.toggle(_selectionClass, true);
      }
    }
  }

  void clear() {
    nodes.clear();
    _selectedNodes.clear();
    _nodeToElementMap.clear();
    element.children.clear();
  }

  Stream<Node> get onClickNode => _clickController.stream;
  Stream<Node> get onDoubleClick => _doubleClickController.stream;

  void scrollToSelection() {
    if (_selectedNodes.isNotEmpty) {
      Node sel = _selectedNodes.last;
      Element e = _nodeToElementMap[sel];
      if (e != null) e.scrollIntoView(); //ScrollAlignment.BOTTOM);
    }
  }
}

class Node<T> {
  final T data;
  final bool canHaveChildren;
  final List<Node> children = [];

  Node(this.data, {this.canHaveChildren: false});

  bool get hasChildren => children.isNotEmpty;
  void add(Node node) => children.add(node);

  bool operator ==(other) => other is Node && data == other.data;
  int get hashCode => data.hashCode;

  String toString() => data.toString();
}
