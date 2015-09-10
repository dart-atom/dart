library atom.outline;

import 'dart:async';
import 'dart:html' as html;

import '../analysis/analysis_server_lib.dart' as analysis;
import '../analysis_server.dart';
import '../atom.dart';
import '../atom_utils.dart';
import '../elements.dart';
import '../projects.dart';
import '../state.dart';
import '../utils.dart';
import '../views.dart';

final String _keyPath = '${pluginId}.showOutlineView';

// TODO: Have a scroll sync button: <span class='badge icon icon-diff-renamed'>

// TODO: Have a close button?

class OutlineController implements Disposable {
  Disposables disposables = new Disposables();

  bool showView = true;

  List<OutlineView> views = [];

  OutlineController() {
    disposables.add(atom.config.observe(_keyPath, null, (val) {
      showView = val;
      for (OutlineView view in views) {
        view._update(showView);
      }
    }));

    disposables.add(atom.commands
        .add('atom-workspace', '${pluginId}:toggle-outline-view', (_) {
      atom.config.setValue(_keyPath, !showView);
    }));

    Timer.run(() {
      disposables.add(atom.workspace.observeTextEditors(_handleEditor));
    });
  }

  void dispose() {
    disposables.dispose();
    for (OutlineView view in views.toList()) {
      view.dispose();
    }
  }

  void _handleEditor(TextEditor editor) {
    String path = editor.getPath();
    if (path == null) return;
    if (!isDartFile(path)) return;
    DartProject project = projectManager.getProjectFor(path);
    if (project == null) return;

    _installInto(editor);
  }

  void _installInto(TextEditor editor) {
    views.add(new OutlineView(this, editor));
  }

  bool _removeView(OutlineView outlineView) => views.remove(outlineView);
}

class OutlineView implements Disposable {
  final OutlineController controller;
  final TextEditor editor;

  html.Element root;
  CoreElement content;
  ListTreeBuilder treeBuilder;
  AnalysisOutline lastOutline;
  StreamSubscriptions subs = new StreamSubscriptions();

  OutlineView(this.controller, this.editor) {
    subs.add(editor.onDidDestroy.listen((_) => dispose()));
    subs.add(editor.onDidChangeCursorPosition.listen(_cursorChanged));
    subs.add(analysisServer.onOutline.listen(_handleOutline));

    root = editor.view['shadowRoot'];

    if (controller.showView) _install();
  }

  bool get installed => content != null;

  void _install() {
    if (content != null) return;

    String title = basename(editor.getPath());

    ViewResizer resizer;

    content = div(c: 'outline-view source')..add([
      div(text: title, c: 'title'),
      treeBuilder = new ListTreeBuilder(_render, hasToggle: false)
          ..toggleClass('outline-tree'),
      resizer = new ViewResizer.createVertical()
    ]);

    treeBuilder.onClickNode.listen(_jumpTo);
    _setupResizer(resizer);

    root.append(content.element);

    if (lastOutline != null) _handleOutline(lastOutline);
  }

  void _setupResizer(ViewResizer resizer) {
    final String prefName = '_outlineResize';

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

  void _uninstall() {
    if (content != null) {
      root.children.remove(content.element);
      content = null;
    }
  }

  void dispose() {
    _uninstall();
    subs.cancel();
    controller._removeView(this);
  }

  void _update(bool showView) {
    if (installed != showView) {
      if (showView) _install();
      if (!showView) _uninstall();
    }
  }

  void _handleOutline(AnalysisOutline data) {
    lastOutline = data;

    if (treeBuilder == null) return;

    if (data.file == editor.getPath()) {
      treeBuilder.clear();

      List nodes = data.outline.children ?? [];
      for (Outline node in nodes) {
        treeBuilder.addNode(_toNode(node));
      }

      _cursorChanged(editor.getCursorBufferPosition());
    }
  }

  // TODO: handle multiple cursors
  void _cursorChanged(Point pos) {
    if (pos == null || treeBuilder == null) return;

    int offset = editor.getBuffer().characterIndexForPosition(pos);
    List<Node> selected = [];

    for (Node node in treeBuilder.nodes) {
      _collectSelected(node, offset, selected);
    }

    treeBuilder.selectNodes(selected);
  }

  void _collectSelected(Node node, int offset, List<Node> selected) {
    Outline o = node.data;

    if (offset >= o.offset && offset < o.offset + o.length) {
      selected.add(node);

      if (node.children != null) {
        for (Node child in node.children) {
          _collectSelected(child, offset, selected);
        }
      }
    }
  }

  Node _toNode(Outline outline) {
    Node n = new Node(outline, canHaveChildren: outline.children != null);
    if (outline.children != null) {
      if (outline.element.kind == 'ENUM') outline.children.clear();

      for (Outline child in outline.children) {
        n.add(_toNode(child));
      }
    }
    return n;
  }

  void _render(Outline item, html.Element intoElement) {
    analysis.Element e = item.element;

    if (e.kind == 'CLASS') {
      intoElement.children.add(
          new html.SpanElement()..classes.addAll(['keyword', 'declaration'])..text = 'class ');
    } else if (e.kind == 'ENUM') {
      intoElement.children.add(
          new html.SpanElement()..classes.addAll(['keyword', 'declaration'])..text = 'enum ');
    } else if (e.kind == 'FUNCTION_TYPE_ALIAS') {
      intoElement.children.add(
          new html.SpanElement()..classes.addAll(['keyword', 'declaration'])..text = 'typedef ');
    }

    // // Type on the left.
    // if (e.returnType != null && e.returnType.isNotEmpty) {
    //   intoElement.children.add(
    //       new html.SpanElement()..classes.add('muted')..text = '${e.returnType} ');
    // }

    if (e.kind == 'GETTER') {
      intoElement.children.add(
          new html.SpanElement()..classes.add('muted')..text = 'get ');
    } else if (e.kind == 'SETTER') {
      intoElement.children.add(
          new html.SpanElement()..classes.add('muted')..text = 'set ');
    }

    html.Element span = new html.AnchorElement();
    span.text = e.name;
    if ((e.flags & 0x20) != 0) span.classes.add('deprecated');
    intoElement.children.add(span);
    if (e.kind == 'CLASS') {
      span.classes.addAll(['support', 'class']);
    }

    if (e.typeParameters != null) {
      intoElement.children.add(
          new html.SpanElement()..classes.add('muted')..text = e.typeParameters);
    }

    if (e.parameters != null) {
      String str = e.parameters.length > 2 ? '(…)' : '()';
      intoElement.children.add(
          new html.SpanElement()..classes.add('muted')..text = str);
    }

    // // Type on the right?
    // if (e.returnType != null && e.returnType.isNotEmpty) {
    //   intoElement.children.add(
    //       new html.SpanElement()..classes.add('muted')..text = ' → ${e.returnType}');
    // }
  }

  void _jumpTo(Node node) {
    Outline outline = node.data;
    analysis.Location location = outline.element.location;
    editorManager.jumpToLocation(location.file,
        location.startLine - 1, location.startColumn - 1, location.length);
    editor.setCursorBufferPosition(
        editor.getBuffer().positionForCharacterIndex(outline.offset));
  }

  // void _scrollSync() {
  //   // TODO: get the current top visible line
  //   // TODO: get the char index
  //   // TODO: get the last node the overlaps that index
  //   // TODO: scroll the cooresponding element into view
  //
  //   if (treeBuilder != null) treeBuilder.scrollToSelection();
  // }
}
