/// A library for a general view implementation in Atom.
library atom.views;

import 'dart:async';
import 'dart:html';
import 'dart:math' as math;

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/workspace.dart' hide Point;
import 'package:atom/utils/disposable.dart';

import 'elements.dart';
import 'state.dart';
import 'utils.dart';

class ViewResizer extends CoreElement {
  StreamController<num> _controller = new StreamController.broadcast();

  Point<num> _offset = new Point(0, 0);

  StreamSubscription _moveSub;
  StreamSubscription _upSub;

  // TODO: Implement the resizer for the top panel.
  ViewResizer.createHorizontal({bool top: false}) : super('div') {
    horizontalSplitter = true;
    if (top) attribute('top');
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

    element.onMouseDown.listen((MouseEvent e) {
      if (e.button != 0) return;

      e.preventDefault();
      _offset = e.offset as Point<num>; // ignore: unnecessary_cast

      _moveSub = document.onMouseMove.listen((MouseEvent e) {
        if (e.button != 0) {
          cancel();
        } else {
          Point<num> current =
            _target.marginEdge.bottomRight - (e.client as Point<num>) + _offset; // ignore: unnecessary_cast
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

class ViewGroupManager implements Disposable {
  Map<String, ViewGroup> _groups = {};

  ViewGroupManager();

  ViewGroup getGroup(String groupName) {
    if (!_groups.containsKey(groupName)) {
      _groups[groupName] = new ViewGroup(groupName);
    }
    return _groups[groupName];
  }

  void addView(String groupName, View view, {bool activate: true}) {
    getGroup(groupName).addView(view, activate: activate);
  }

  void activateView(String viewId) {
    for (ViewGroup group in _groups.values) {
      if (group.hasViewId(viewId)) {
        group.activateViewById(viewId);
      }
    }
  }

  void activate(View view) {
    for (ViewGroup group in _groups.values) {
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

  View getViewById(String id) {
    for (ViewGroup group in _groups.values) {
      if (group.hasViewId(id)) return group.getViewById(id);
    }

    return null;
  }

  void dispose() {
    for (ViewGroup group in _groups.values.toList()) {
      group.dispose();
    }
  }

  void removeViewId(String id) {
    for (ViewGroup group in _groups.values) {
      if (group.hasViewId(id)) {
        group.removeView(group.getViewById(id));
      }
    }
  }
}

class ViewGroup implements Disposable {
  static const String top = 'top';
  static const String right = 'right';
  static const String bottom = 'bottom';

  static const int _defaultWidth = 300;
  static const int _defaultHeight = 125;

  final String name;
  final SelectionGroup<View> views = new SelectionGroup();

  CoreElement root;
  CoreElement tabHeader;
  CoreElement tabContainer;

  Panel _panel;

  View _active;
  List<View> _history = [];

  ViewGroup(this.name) {
    bool topPanel = name == top;
    bool rightPanel = name == right;
    bool bottomPanel = name == bottom;

    String c = 'atom-view tree-view';
    root = div(c: c)..layoutVertical();
    ViewResizer resizer;

    root.add([
      tabHeader = ul(c: 'list-inline tab-bar inset-panel')..hidden(),
      tabContainer = div(c: 'tab-container')..flex(),
      resizer = rightPanel
          ? new ViewResizer.createVertical()
          : new ViewResizer.createHorizontal(top: !bottomPanel)
    ]);

    if (rightPanel) {
      _panel = atom.workspace.addRightPanel(item: root.element, visible: false);
    } else if (topPanel) {
      _panel = atom.workspace.addTopPanel(item: root.element, visible: false);
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

  void addView(View view, {bool activate: true}) {
    if (views.items.contains(view)) return;

    view.group = this;

    view.handleDeactivate();
    tabContainer.add(view.root);
    views.add(view);
    if (views.length > 1 && activate) views.setSelection(view);
  }

  bool hasViewId(String viewId) => getViewById(viewId) != null;

  bool hasView(View view) => views.items.contains(view);

  View getViewById(String viewId) {
    return views.items.firstWhere((view) => view.id == viewId, orElse: () => null);
  }

  void activateViewById(String viewId) {
    View view = getViewById(viewId);
    if (view != null) views.setSelection(view);
  }

  void activateView(View view) {
    views.setSelection(view);
  }

  bool isActiveId(String viewId) {
    return _active != null ? _active.id == viewId : false;
  }

  void removeView(View view) {
    if (view != null) views.remove(view);
  }

  void _onViewAdded(View view) {
    if (hidden && views.items.isNotEmpty) _setVisible(true);
    tabHeader.hidden(views.length < 2);
    for (View v in views.items) {
      v._closeButton.hidden(views.length != 1);
    }
    tabHeader.add(view.tabElement);
  }

  void _onActiveChanged(View view) {
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

  void _onViewRemoved(View view) {
    _history.remove(view);
    if (showing && views.items.isEmpty) _setVisible(false);
    tabHeader.hidden(views.length < 2);
    for (View v in views.items) {
      v._closeButton.hidden(views.length != 1);
    }
    view.root.dispose();
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

    for (View view in views.items) {
      view.dispose();
    }
  }
}

abstract class View implements Disposable {
  final CoreElement root;
  final CoreElement toolbar;
  final CoreElement content;

  CoreElement tabElement;
  CloseButton _closeButton;

  ViewGroup group;

  View() :
      root = div(c: 'tab-content'),
      toolbar = div(),
      content = div() {
    root.add([
      div(c: 'button-bar')..flex()..add([
        toolbar,
        _closeButton = new CloseButton()..click(handleClose)
      ]),
      content
    ]);

    tabElement = li(c: 'tab')..add([
      div(text: label, c: 'title'),
      div(c: 'close-icon')..click(handleClose)
    ])..click(_handleTab)..element.attributes['data-type'] = 'ViewPartEditor';
  }

  String get id;
  String get label;

  void dispose();

  void handleActivate() {
    root.toggleAttribute('hidden', false);
    tabElement.toggleClass('active', true);
  }

  void handleDeactivate() {
    root.toggleAttribute('hidden', true);
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

class ViewSection extends CoreElement {
  CoreElement title;
  CoreElement subtitle;

  ViewSection() : super('div', classes: 'view-section') {
    title = add(title = div(c: 'view-title'));
    subtitle = add(div(c: 'view-subtitle'));

    layoutVertical();
  }
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

      e.onClick.listen((Event event) {
        if (!event.defaultPrevented) _clickController.add(node);
      });
      e.onDoubleClick.listen((Event event) {
        if (!event.defaultPrevented) _doubleClickController.add(node);
      });
      element.add(d);

      CoreElement u = ul(c: 'list-tree');
      element.add(u);

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

  int get decendentCount => children.fold(1, (int val, Node n) {
    return val + n.decendentCount;
  });

  String toString() => data.toString();
}

/// Implement double tap escape to close.
class DoubleCancelCommand implements Disposable {
  Function handleCancel;
  Disposable _command;
  Timer _timer;

  DoubleCancelCommand(this.handleCancel) {
    _command = atom.commands.add('atom-workspace', 'core:cancel', _handleCancel);
  }

  void _handleCancel(AtomEvent _) {
    if (_timer != null) {
      handleCancel();
    } else {
      _timer = new Timer(new Duration(milliseconds: 750), () => _timer = null);
    }
  }

  void dispose() => _command.dispose();
}
