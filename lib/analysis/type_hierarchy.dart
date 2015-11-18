
library atom.type_hierarchy;

import 'dart:html' as html show Element, SpanElement;

import 'package:logging/logging.dart';

import '../analysis_server.dart';
import '../atom.dart';
import '../elements.dart';
import '../state.dart';
import '../utils.dart';
import '../views.dart';
import 'analysis_server_lib.dart';

final Logger _logger = new Logger('type_hierarchy');

class TypeHierarchyHelper implements Disposable {
  Disposable _command;

  TypeHierarchyHelper() {
    _command = atom.commands.add(
        'atom-text-editor', 'dartlang:type-hierarchy', _handleHierarchy);
  }

  void dispose() => _command.dispose();

  void _handleHierarchy(AtomEvent event) => _handleHierarchyEditor(event.editor);

  void _handleHierarchyEditor(TextEditor editor) {
    String path = editor.getPath();
    Range range = editor.getSelectedBufferRange();
    int offset = editor.getBuffer().characterIndexForPosition(range.start);

    Job job = new AnalysisRequestJob('type hierarchy', () {
      return analysisServer.getTypeHierarchy(path, offset).then((result) {
        if (result == null) return;

        if (result.hierarchyItems == null) {
          atom.beep();
          return;
        }

        TypeHierarchyView.showHierarchy(result);
      });
    });
    job.schedule();
  }
}

class TypeHierarchyView extends View2 {
  static TypeHierarchyView _singleton;

  static void showHierarchy(TypeHierarchyResult result) {
    if (_singleton == null) {
      _singleton = new TypeHierarchyView();
      _singleton._buildHierarchy(result);
      viewGroupManager.addView('right', _singleton);
    } else {
      _singleton._buildHierarchy(result);
      viewGroupManager.activate(_singleton);
    }
  }

  CoreElement element;
  ListTreeBuilder treeBuilder;
  List<TypeHierarchyItem> _items;

  TypeHierarchyView() {
    element = div(c: 'type-hierarchy')..layoutVertical();
    treeBuilder = element.add(new ListTreeBuilder(_render)..flex());
    treeBuilder.onClickNode.listen(_jumpTo);
  }

  String get id => 'typeHierarchy';

  String get label => 'Type Hierarchy';

  void dispose() {
    _singleton = null;
  }

  void _buildHierarchy(TypeHierarchyResult result) {
    treeBuilder.clear();

    List<TypeHierarchyItem> items = result.hierarchyItems;
    this._items = items;

    TypeHierarchyItem item = items.first;
    Node node = new Node(item, canHaveChildren: _hasSubclasses(item));
    Node targetNode = node;

    if (node.canHaveChildren) {
      for (int ref in _sort(items, item.subclasses)) {
        node.add(_createChild(items, items[ref]));
      }
    }

    while (item.superclass != null) {
      TypeHierarchyItem superItem = items[item.superclass];
      // Show a parent interface if there is no explicit extends.
      if (superItem.superclass == null && item.interfaces.isNotEmpty) {
        superItem = items[item.interfaces.first];
      }
      Node superNode = new Node(superItem, canHaveChildren: true);
      superNode.add(node);
      item = superItem;
      node = superNode;
    }

    treeBuilder.addNode(node);
    treeBuilder.selectNode(targetNode);
  }

  Node _createChild(List<TypeHierarchyItem> items, TypeHierarchyItem item) {
    Node node = new Node(item, canHaveChildren: _hasSubclasses(item));

    if (node.canHaveChildren) {
      for (int ref in _sort(items, item.subclasses)) {
        TypeHierarchyItem i = items[ref];
        // This works around an issue in older versions of the analysis server.
        if (i != item) {
          node.add(_createChild(items, items[ref]));
        }
      }
    }

    return node;
  }

  List<int> _sort(List<TypeHierarchyItem> items, List<int> subclasses) {
    return subclasses..sort((int aIndex, int bIndex) {
      TypeHierarchyItem a = items[aIndex];
      TypeHierarchyItem b = items[bIndex];

      String aName = a.displayName != null ? a.displayName : a.classElement.name;
      String bName = b.displayName != null ? b.displayName : b.classElement.name;

      return aName.compareTo(bName);
    });
  }

  void _jumpTo(Node node) {
    Location location = (node.data as TypeHierarchyItem).classElement.location;
    if (location != null) {
      editorManager.jumpToLocation(location.file,
          location.startLine - 1, location.startColumn - 1, location.length);
    } else {
      atom.beep();
    }
  }

  bool _hasSubclasses(TypeHierarchyItem item) =>
      item.subclasses != null && item.subclasses.length > 0;

  void _render(TypeHierarchyItem item, html.Element intoElement) {
    bool isAbstract = (item.classElement.flags & 0x01) != 0;
    bool isDeprecated = (item.classElement.flags & 0x20) != 0;

    html.SpanElement span = new html.SpanElement();
    span.text = item.displayName != null ? item.displayName : item.classElement.name;
    if (isAbstract) span.classes.add('hierarchy-abstract');
    if (isDeprecated) span.classes.add('hierarchy-deprecated');
    intoElement.children.add(span);

    if (item.mixins.isNotEmpty || item.interfaces.isNotEmpty) {
      StringBuffer buf = new StringBuffer();

      if (item.interfaces.isNotEmpty) {
        buf.write(' '); //'implements ');
        buf.write(item.interfaces.map((i) => _items[i].classElement.name).join(', '));
      }

      if (item.mixins.isNotEmpty) {
        if (buf.isNotEmpty) buf.write(', ');
        buf.write('with ');
        buf.write(item.mixins.map((i) => _items[i].classElement.name).join(', '));
      }

      span = new html.SpanElement();
      span.text = buf.toString();
      span.classes.add('hierarchy-muted');
      intoElement.children.add(span);
    }
  }
}
