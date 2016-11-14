library atom.outline;

import 'dart:async';
import 'dart:html' as html;

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../analysis/analysis_server_lib.dart' as analysis;
import '../analysis_server.dart';
import '../elements.dart';
import '../linter.dart';
import '../projects.dart';
import '../state.dart';
import '../utils.dart';
import '../views.dart';

final String _keyPath = '${pluginId}.showOutlineView';

final Logger _logger = new Logger('atom.outline');

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

    disposables.add(
      atom.commands.add('atom-workspace', '${pluginId}:toggle-outline-view', (_) {
        _close();
      })
    );

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
    if (!isDartFile(path)) return;

    _installInto(editor);
  }

  void _installInto(TextEditor editor) {
    views.add(new OutlineView(this, editor));
  }

  bool _removeView(OutlineView outlineView) => views.remove(outlineView);

  void _close() => atom.config.setValue(_keyPath, !showView);

  analysis.AnalysisOutline _getLastOutlineData(String path) {
    for (OutlineView view in views) {
      if (path == view.path && view.lastOutline != null) {
        return view.lastOutline;
      }
    }

    return null;
  }
}

class OutlineView implements Disposable {
  final OutlineController controller;
  final TextEditor editor;

  html.Element root;
  CoreElement content;
  CoreElement fileType;
  CoreElement title;
  ListTreeBuilder treeBuilder;
  CoreElement errorArea;
  _ErrorsList errorsList;
  AnalysisOutline lastOutline;
  StreamSubscriptions subs = new StreamSubscriptions();

  List<Outline> _topLevel = [];

  OutlineView(this.controller, this.editor) {
    subs.add(editor.onDidDestroy.listen((_) => dispose()));
    subs.add(editor.onDidChangeCursorPosition.listen(_cursorChanged));
    subs.add(analysisServer.onOutline.listen(_handleOutline));
    subs.add(onProcessedErrorsChanged.listen(_handleErrorsChanged));

    if (atomUsesShadowDOM) {
      root = editor.view['shadowRoot'];
      if (root == null) {
        _logger.warning("The editor's shadow root is null");
      }
    }

    if (controller.showView) _install();
  }

  bool get installed => content != null;

  String get path => editor.getPath();

  void _install() {
    if (root == null) return;
    if (content != null) return;

    ViewResizer resizer;

    content = div(c: 'outline-view source')..add([
      div(c: 'title-container')..add([
        div(c: 'title-text')..add([
          fileType = span(c: 'keyword'),
          title = span()
        ]),
        div(c: 'close-button')..click(controller._close)
      ]),
      treeBuilder = new ListTreeBuilder(_render, hasToggle: false)
        ..toggleClass('outline-tree')
        ..toggleClass('selection'),
      errorArea = div(c: 'outline-errors')..hidden(true)..add([
        errorsList = new _ErrorsList(this)
      ]),
      resizer = new ViewResizer.createVertical()
    ]);

    treeBuilder.onClickNode.listen(_jumpTo);
    treeBuilder.setSelectionClass('region');
    _setupResizer(resizer);

    root.append(content.element);

    if (lastOutline != null) {
      _handleOutline(lastOutline);
    } else {
      // Ask the manager for the outline data.
      _handleOutline(controller._getLastOutlineData(path));
    }

    _handleErrorsChanged();
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
    if (content != null && root != null) {
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
    if (data == null || data.file != editor.getPath()) return;

    lastOutline = data;

    if (treeBuilder == null) return;

    // Update the title.
    if (data.libraryName == null) {
      fileType.text = '';
      title.text = fs.basename(editor.getPath());
    } else if (data.kind == 'PART') {
      fileType.text = 'part of ';
      title.text = data.libraryName;
    } else {
      fileType.text = 'library ';
      title.text = data.libraryName;
    }

    treeBuilder.clear();

    _topLevel.clear();

    if (data.outline == null) {
      treeBuilder.add(div(text: 'outline not available', c: 'comment'));
    } else {
      List<Outline> nodes = data.outline.children ?? <Outline>[];
      for (Outline node in nodes) {
        _topLevel.add(node);
        treeBuilder.addNode(_toNode(node));
      }
    }

    _cursorChanged(editor.getCursorBufferPosition());
  }

  void _handleErrorsChanged([List<analysis.AnalysisError> errors]) {
    if (errorsList == null) return;

    if (errors == null) errors = (deps[DartLinterConsumer] as DartLinterConsumer).errors;
    errorsList.updateWith(errors);
    errorArea.hidden(!errorsList.hasErrors);
  }

  void _cursorChanged(Point pos) {
    if (pos == null || treeBuilder == null) return;

    int offset = editor.getBuffer().characterIndexForPosition(pos);
    List<Node> selected = [];

    for (Node node in treeBuilder.nodes) {
      _collectSelected(node, offset, selected);
    }

    treeBuilder.selectNodes(selected.isEmpty ? selected : [selected.last]);
    treeBuilder.scrollToSelection();
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

    // static class members
    bool isStatic = false;
    if (((e.flags & 0x08) != 0) && !_topLevel.contains(item)) {
      isStatic = true;
    }

    if (e.kind == 'CLASS') {
      intoElement.children.add(new html.SpanElement()
          ..classes.add('keyword')
          ..text = 'class ');
    } else if (e.kind == 'ENUM') {
      intoElement.children.add(new html.SpanElement()
          ..classes.add('keyword')
          ..text = 'enum ');
    } else if (e.kind == 'FUNCTION_TYPE_ALIAS') {
      intoElement.children.add(new html.SpanElement()
          ..classes.add('keyword')
          ..text = 'typedef ');
    }

    if (e.kind == 'GETTER') {
      intoElement.children.add(new html.SpanElement()
          ..classes.add('comment')
          ..text = 'get ');
    } else if (e.kind == 'SETTER') {
      intoElement.children.add(new html.SpanElement()
          ..classes.add('comment')
          ..text = 'set ');
    }

    html.Element span = new html.AnchorElement();
    if ((e.flags & 0x20) != 0) span.classes.add('outline-deprecated');
    if (isStatic) span.classes.add('outline-static');
    intoElement.children.add(span);

    String name = e.name;

    if (e.kind == 'CLASS') span.classes.addAll(['support', 'class']);
    if (e.kind == 'CONSTRUCTOR') span.classes.addAll(['support', 'class']);
    if (e.kind == 'FUNCTION' || e.kind == 'METHOD' || e.kind == 'GETTER' ||
        e.kind == 'SETTER') {
      span.classes.addAll(['entity', 'name', 'function']);
    }

    if (e.parameters != null && e.kind != 'GETTER') {
      String str = e.parameters.length > 2 ? '(…)' : '()';
      // intoElement.children.add(
      //     new html.SpanElement()../*classes.add('muted')..*/text = str);
      name += str;
    }

    span.text = name;

    if (e.typeParameters != null) {
      intoElement.children.add(
          new html.SpanElement()..classes.add('comment')..text = e.typeParameters);
      //name += e.typeParameters;
    }

    if (e.returnType != null && e.returnType.isNotEmpty) {
      String type = e.returnType;
      int index = type.indexOf('<');
      if (index != -1) type = '${type.substring(0, index)}<…>';
      intoElement.children.add(
          new html.SpanElement()..classes.add('comment')..text = ' → ${type}');
    }
  }

  void _jumpTo(Node node) => _jumpToLocation(node.data.element.location);

  void _jumpToLocation(analysis.Location location) {
    Range range = new Range.fromPoints(
      new Point.coords(location.startLine - 1, location.startColumn - 1),
      new Point.coords(location.startLine - 1, location.startColumn - 1 + location.length)
    );
    editor.setSelectedBufferRange(range);
  }
}

class _ErrorsList extends CoreElement {
  final OutlineView view;
  final String path;

  _ErrorsList(OutlineView inView) :
    view = inView,
    path = inView.path,
    super('div', classes: 'errors-list');

  bool get hasErrors => element.children.isNotEmpty;

  void updateWith(List<analysis.AnalysisError> errors) {
    clear();

    for (analysis.AnalysisError error in errors) {
      if (path != error.location.file) continue;

      add(div(c: 'outline-error-item')..add([
        span(
          text: error.severity.toLowerCase(),
          c: 'item-${error.severity.toLowerCase()}'
        ),
        span(text: ' ${error.message}', c: 'comment')
      ])..click(() => view._jumpToLocation(error.location)));
    }
  }
}
