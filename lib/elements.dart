// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.elements;

import 'dart:async';
import 'dart:html';
import 'dart:math' as math;

import 'atom.dart' hide Point;
import 'state.dart';
import 'utils.dart';

/// Finds the first descendant element of this document with the given id.
Element queryId(String id) => querySelector('#${id}');

/// Finds the first descendant element of this document with the given id.
Element $(String id) => querySelector('#${id}');

CoreElement button({String text, String c, String a}) =>
    new CoreElement('button', text: text, classes: c, attributes: a);

CoreElement div({String text, String c, String a}) =>
    new CoreElement('div', text: text, classes: c, attributes: a);

CoreElement span({String text, String c, String a}) =>
    new CoreElement('span', text: text, classes: c, attributes: a);

CoreElement img({String text, String c, String a}) =>
    new CoreElement('img', text: text, classes: c, attributes: a);

CoreElement ol({String text, String c, String a}) =>
    new CoreElement('ol', text: text, classes: c, attributes: a);

CoreElement ul({String text, String c, String a}) =>
    new CoreElement('ul', text: text, classes: c, attributes: a);

CoreElement li({String text, String c, String a}) =>
    new CoreElement('li', text: text, classes: c, attributes: a);

CoreElement para({String text, String c, String a}) =>
    new CoreElement('p', text: text, classes: c, attributes: a);

class CoreElement {
  final Element element;

  CoreElement.from(this.element);

  CoreElement(String tag, {String text, String classes, String attributes}) :
      element = new Element.tag(tag) {
    if (text != null) element.text = text;
    if (classes != null) element.classes.addAll(classes.split(' '));
    if (attributes != null) attributes.split(' ').forEach(attribute);
  }

  String get tag => element.tagName;

  String get id => attributes['id'];
  set id(String value) => setAttribute('id', value);

  String get src => attributes['src'];
  set src(String value) => setAttribute('src', value);

  bool hasAttribute(String name) => element.attributes.containsKey(name);

  void attribute(String name, [bool value]) {
    if (value == null) value = !element.attributes.containsKey(name);

    if (value) {
      element.setAttribute(name, '');
    } else {
      element.attributes.remove(name);
    }
  }

  void toggleAttribute(String name, [bool value]) => attribute(name, value);

  Map<String, String> get attributes => element.attributes;

  void setAttribute(String name, [String value = '']) =>
      element.setAttribute(name, value);

  String clearAttribute(String name) => element.attributes.remove(name);

  void icon(String iconName) =>
      element.classes.addAll(['icon', 'icon-${iconName}']);

  void clazz(String _class) {
    if (_class.contains(' ')) {
      throw new ArgumentError('spaces not allowed in class names');
    }
    element.classes.add(_class);
  }

  void toggleClass(String name, [bool value]) {
    element.classes.toggle(name, value);
  }

  set text(String value) {
    element.text = value;
  }

  // Atom classes.
  void block() => clazz('block');
  void inlineBlock() => clazz('inline-block');
  void inlineBlockTight() => clazz('inline-block-tight');

  /// Add the given child to this element's list of children. [child] must be
  /// either a `CoreElement` or an `Element`.
  dynamic add(dynamic child) {
    if (child is List) {
      return child.map((c) => add(c)).toList();
    } else if (child is CoreElement) {
      element.children.add(child.element);
    } else if (child is Element) {
      element.children.add(child);
    } else {
      throw new ArgumentError('argument type not supported');
    }
    return child;
  }

  void hidden([bool value]) => attribute('hidden', value);

  String get label => attributes['label'];
  set label(String value) => setAttribute('label', value);

  bool get disabled => hasAttribute('disabled');
  set disabled(bool value) => attribute('disabled', value);

  // Layout types.
  void layout() => attribute('layout');
  void horizontal() => attribute('horizontal');
  void vertical() => attribute('vertical');

  void layoutHorizontal() {
    setAttribute('layout');
    setAttribute('horizontal');
  }

  void layoutVertical() {
    setAttribute('layout');
    setAttribute('vertical');
  }

  // Layout params.
  void fit() => attribute('fit');
  void flex([int flexAmount]) {
    attribute('flex', true);

    if (flexAmount != null) {
      if (flexAmount == 1) attribute('one', true);
      else if (flexAmount == 2) attribute('two', true);
      else if (flexAmount == 3) attribute('three', true);
      else if (flexAmount == 4) attribute('four', true);
      else if (flexAmount == 5) attribute('five', true);
    }
  }

  Stream<MouseEvent> get onClick => element.onClick;

  /// Subscribe to the [onClick] event stream with a no-arg handler.
  StreamSubscription<Event> click(void handle()) => onClick.listen((_) => handle());

  void dispose() {
    if (element.parent == null) return;

    if (element.parent.children.contains(element)) {
      try {
        element.parent.children.remove(element);
      } catch (e) {
      }
    }
  }

  String toString() => element.toString();
}

class ProgressElement extends CoreElement {
  CoreElement _progress;

  ProgressElement() : super('div') {
    block();
    _progress = add(new CoreElement('progress')..inlineBlock());
  }

  set value(int val) => _progress.setAttribute('value', val.toString());
  set max(int val) => _progress.setAttribute('max', val.toString());
}

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
    _targetSize = verticalSplitter ? size.x : size.y;
  }

  Element get _target => element.parent;

  num _minSize(Element e) {
    CssStyleDeclaration style = e.getComputedStyle();
    String str = verticalSplitter ? style.minWidth : style.minHeight;
    if (str.isEmpty) return 0;
    if (str.endsWith('px')) str = str.substring(0, str.length - 2);
    return num.parse(str);
  }

  num get _targetSize {
    CssStyleDeclaration style = _target.getComputedStyle();
    String str = verticalSplitter ? style.width : style.height;
    if (str.endsWith('px')) str = str.substring(0, str.length - 2);
    return num.parse(str);
  }

  set _targetSize(num size) {
    final num currentPos = _controller.hasListener ? position : null;

    size = math.max(size, _minSize(element));

    if (verticalSplitter) {
      _target.style.width = '${size}px';
    } else {
      _target.style.height = '${size}px';
    }

    if (_controller.hasListener) {
      num newPos = position;
      if (currentPos != newPos) _controller.add(newPos);
    }
  }
}

class CloseButton extends CoreElement {
  CloseButton() : super('div', classes: 'close-button');
}

class TitledModelDialog implements Disposable {
  Panel _panel;
  Disposable _cancelCommand;

  CoreElement title;
  CoreElement content;

  TitledModelDialog(String inTitle, {String classes}) {
    CoreElement closeButton;

    CoreElement root = div(c: classes)..add([
      div(c: 'modal-header')..layoutHorizontal()..add([
        title = div(text: inTitle, c: 'text-highlight')..flex(),
        closeButton = new CloseButton()
      ]),
      content = div()
    ]);

    closeButton.onClick.listen((e) {
      hide();
      e.preventDefault();
    });

    _panel = atom.workspace.addModalPanel(item: root.element);
    _cancelCommand = atom.commands.add('atom-workspace', 'core:cancel', (_) => hide());
  }

  void show() => _panel.show();

  void hide() => _panel.hide();

  void dispose() {
    _panel.invoke('destroy');
    _cancelCommand.dispose();
  }
}

class AtomView implements Disposable  {
  static const int _defaultSize = 250;

  Panel _panel;
  Disposable _cancelCommand;

  CoreElement root;
  CoreElement title;
  CoreElement content;

  AtomView(String inTitle, {String classes, String prefName,
      bool rightPanel: true, bool cancelCloses: true, bool showTitle: true}) {
    CoreElement closeButton;
    ViewResizer resizer;

    String c = 'atom-view tree-view';
    if (classes != null) c = '${c} ${classes}';

    root = div(c: c)..layoutVertical();

    if (showTitle) {
      root.add(
        div(c: 'panel-heading')..layoutHorizontal()..add([
          title = div(text: inTitle, c: 'text-highlight view-header')..flex(),
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

    if (prefName != null) {
      int pos = state[prefName];
      resizer.position = pos != null ? pos : _defaultSize;
      resizer.onPositionChanged.listen((pos) {
        state[prefName] = pos;
      });
    } else {
      resizer.position = _defaultSize;
    }

    if (rightPanel) {
      _panel = atom.workspace.addRightPanel(item: root.element);
    } else {
      _panel = atom.workspace.addBottomPanel(item: root.element);
    }

    if (cancelCloses) {
      _cancelCommand = atom.commands.add('atom-workspace', 'core:cancel', (_) => _handleCancel());
    }
  }

  Timer _timer;

  void _handleCancel() {
    // Double tap escape to close.
    if (_timer != null) {
      hide();
    } else {
      _timer = new Timer(new Duration(milliseconds: 250), () => _timer = null);
    }
  }

  bool isVisible() => _panel.isVisible();
  void show() => _panel.show();
  void hide() => _panel.hide();

  void dispose() {
    _panel.invoke('destroy');
    _cancelCommand.dispose();
  }
}

class ListTreeBuilder extends CoreElement {
  final StreamController<Node> _selectedController = new StreamController.broadcast();
  final StreamController<Node> _doubleClickController = new StreamController.broadcast();
  final Function render;

  Node _selectedNode;
  Map<Node, Element> _nodeToElementMap = {};

  // focusable-panel ?
  ListTreeBuilder(this.render) :
      super('div', classes: 'list-tree has-collapsable-children');

  Node get selectedNode => _selectedNode;

  void addNode(Node node) => _addNode(this, node);

  void _addNode(CoreElement parent, Node node) {
    if (!node.canHaveChildren) {
      CoreElement element = li(c: 'list-item');
      Element e = element.element;
      render(node.data, e);
      _nodeToElementMap[node] = e;
      e.onClick.listen((_) => selectNode(node));
      e.onDoubleClick.listen((_) => _doubleClickController.add(node));
      parent.add(element);
    } else {
      CoreElement element = li(c: 'list-nested-item');
      parent.add(element);

      CoreElement d = div(c: 'list-item');
      Element e = d.element;
      render(node.data, e);
      _nodeToElementMap[node] = e;
      e.onClick.listen((_) => selectNode(node));
      e.onDoubleClick.listen((MouseEvent event) {
        if (!event.defaultPrevented) _doubleClickController.add(node);
      });
      element.add(d);

      CoreElement u = ul(c: 'list-tree');
      element.add(u);

      e.onClick.listen((MouseEvent e) {
        // Only respond to clicks on the toggle arrow.
        if (e.offset.x < 12) {
          element.toggleClass('collapsed');
          e.preventDefault();
          e.stopPropagation();
        }
      });

      for (Node child in node.children) {
        _addNode(u, child);
      }
    }
  }

  void selectNode(Node node) {
    // .selected uses absolute positioning...
    if (_selectedNode != null) {
      Element e = _nodeToElementMap[_selectedNode];
      if (e != null) {
        e.classes.toggle('tree-selected', false);
      }
    }

    _selectedNode = node;

    if (_selectedNode != null) {
      Element e = _nodeToElementMap[_selectedNode];
      if (e != null) {
        e.classes.toggle('tree-selected', true);
      }
    }

    _selectedController.add(selectedNode);
  }

  void clear() {
    _nodeToElementMap.clear();
    element.children.clear();
  }

  Stream<Node> get onSelected => _selectedController.stream;
  Stream<Node> get onDoubleClick => _doubleClickController.stream;
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
