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

/// A view that is docked on atom's side docks.
abstract class DockedView {
  final CoreElement root;
  final CoreElement content;
  final String id;

  String get label;
  String get defaultLocation => 'right';

  Item item;

  DockedView(this.id, this.content) : root = div() {
    root
      ..toggleClass('atom-view')
      ..toggleClass('tree-view')
      ..add(content);
  }

  void handleClose() {}
  void dispose() {}
}

/// Manages a single or multiple DockedView.
abstract class DockedViewManager<T extends DockedView> implements Disposable {
  final String prefixUri;

  Disposables disposables = new Disposables();
  StreamSubscriptions subs = new StreamSubscriptions();

  DockedViewManager(this.prefixUri) {
    atom.workspace.addOpener(_createView);

    subs.add(atom.workspace.onDidDestroyPaneItem
        .listen((event) {
      Item item = new Item(event['item']);
      if (item.uri != null && item.uri.startsWith(prefixUri)) {
        viewFromUri(item.uri)?.handleClose();
      }
    }));
  }

  String viewUri(String id) => '$prefixUri/$id';
  String viewId(String uri) => uri.replaceFirst("$prefixUri/", '');

  Map<String, T> views = {};
  Map<String, dynamic> datas = {};
  T viewFromId(String id) => views[viewUri(id)];
  T viewFromUri(String uri) => views[uri];
  T instantiateView(String id, [dynamic data]);

  T get singleton => viewFromId('0');

  void dispose() {
    subs.dispose();
    disposables.dispose();
  }

  dynamic _createView(String uri, Map options) {
    if (uri.startsWith(prefixUri)) {
      DockedView v = views[uri] = instantiateView(viewId(uri), datas[uri]);
      v.item = new Item.fromFields(
        element: v.root.element,
        title: v.label,
        uri: uri,
        defaultLocation: v.defaultLocation,
        destroy: v.dispose
      );
      return v.item.obj;
    }
    return null;
  }

  void showView({String id: '0', dynamic data}) {
    datas[viewUri(id)] = data;
    atom.workspace.open(viewUri(id), options: {
      'searchAllPanes': true,
    });
  }

  void removeView({String id: '0'}) {
    // JsObject item = viewFromId(id)?.item;
    Item item = viewFromId(id)?.item;
    if (item == null) return;
    Pane p = atom.workspace.paneForItem(item);
    if (p == null) return;
    p.destroyItem(item);
  }
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
