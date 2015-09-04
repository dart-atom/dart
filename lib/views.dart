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

  Point _offset = new Point(0, 0);

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
      _offset = e.offset;

      _moveSub = document.onMouseMove.listen((MouseEvent e) {
        if (e.which != 1) {
          cancel();
        } else {
          Point current = _target.marginEdge.bottomRight - e.client + _offset;
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
  static const int _defaultSize = 250;

  static ViewGroupManager get groupManager {
    if (deps[ViewGroupManager] == null) deps[ViewGroupManager] = new ViewGroupManager();
    return deps[ViewGroupManager];
  }

  final String groupName;

  Panel _panel;
  Disposable _cancelCommand;
  StreamSubscriptions subs = new StreamSubscriptions();

  CoreElement root;
  CoreElement title;
  CoreElement content;

  AtomView(String inTitle, {String classes, String prefName,
      bool rightPanel: true, bool cancelCloses: true, bool showTitle: true,
      this.groupName}) {
    CoreElement closeButton;
    ViewResizer resizer;

    String c = 'atom-view tree-view';
    if (classes != null) c = '${c} ${classes}';

    root = div(c: c)..layoutVertical();

    if (showTitle) {
      root.add(
        div(c: 'view-header')..layoutHorizontal()..add([
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
      resizer = rightPanel ? new ViewResizer.createVertical() : new ViewResizer.createHorizontal()
    ]);

    if (prefName == null && groupName != null) prefName = groupName;
    _setupResizer(prefName, resizer);

    if (rightPanel) {
      _panel = atom.workspace.addRightPanel(item: root.element, visible: false);
    } else {
      _panel = atom.workspace.addBottomPanel(item: root.element, visible: false);
    }

    if (cancelCloses) {
      _cancelCommand = atom.commands.add('atom-workspace', 'core:cancel', (_) => _handleCancel());
    }

    if (groupName != null) {
      groupManager.addView(groupName, this);
    }

    show();
  }

  void _setupResizer(String prefName, ViewResizer resizer) {
    if (prefName == null) {
      resizer.position = _defaultSize;
    } else {
      if (state[prefName] != null) resizer.position = state[prefName];

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
      _timer = new Timer(new Duration(milliseconds: 500), () => _timer = null);
    }
  }

  bool isVisible() => _panel.isVisible();

  void show() {
    _panel.show();

    groupManager.viewShowing(groupName, this);
  }

  void hide() => _panel.hide();

  void dispose() {
    groupManager.removeView(groupName, this);
    _panel.invoke('destroy');
    _cancelCommand.dispose();
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

  void viewShowing(String name, AtomView view) {
    if (_groups.containsKey(name)) {
      _groups[name].viewShowing(view);
    }
  }

  void removeView(String name, AtomView view) {
    if (_groups.containsKey(name)) {
      _groups[name].removeView(view);
    }
  }
}

class ViewGroup {
  final String name;
  final List<AtomView> views = [];

  ViewGroup(this.name);

  void addView(AtomView view) {
    views.add(view);
  }

  void viewShowing(AtomView view) {
    for (AtomView v in views) {
      if (v != view) {
        if (v.isVisible()) v.hide();
      }
    }
  }

  void removeView(AtomView view) {
    views.remove(view);
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

  ListTreeBuilder(this.render, {this.hasToggle: true}) :
      super('div', classes: 'list-tree has-collapsable-children');

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
      e.onDoubleClick.listen((MouseEvent event) {
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
        if (e != null) e.classes.toggle('tree-selected', false);
      }
    }

    _selectedNodes.clear();
    _selectedNodes.addAll(selected);

    if (_selectedNodes.isNotEmpty) {
      for (Node n in _selectedNodes) {
        Element e = _nodeToElementMap[n];
        if (e != null) e.classes.toggle('tree-selected', true);
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
      if (e != null) e.scrollIntoView(); //ScrollAlignment.TOP);
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
