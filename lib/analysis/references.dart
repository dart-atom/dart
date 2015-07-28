
library atom.references;

import 'dart:async';
import 'dart:collection';
import 'dart:html' as html show DivElement, Element, SpanElement;
import 'dart:math' as math;

import 'package:logging/logging.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../elements.dart';
import '../state.dart';
import '../utils.dart';
import 'analysis_server_gen.dart';

final Logger _logger = new Logger('references');

// TODO: Clean up SDK references.
// TODO: Clean up .pub-cache references.

class FindReferencesHelper implements Disposable {
  Disposable _command;
  FindReferencesView _view;

  FindReferencesHelper() {
    _command = atom.commands.add(
        'atom-text-editor', 'dartlang:find-references', _handleReferences);
  }

  void dispose() {
    _command.dispose();
    if (_view != null) _view.dispose();
  }

  void _handleReferences(AtomEvent event) => _handleReferencesEditor(event.editor);

  void _handleReferencesEditor(TextEditor editor) {
    if (analysisServer.isActive) {
      String path = editor.getPath();
      Range range = editor.getSelectedBufferRange();
      int offset = editor.getBuffer().characterIndexForPosition(range.start);

      analysisServer.findElementReferences(path, offset, false).then(
          (FindElementReferencesResult result) {
        if (result.id == null) {
          _beep();
        } else {
          // TODO: Flash the token that we're finding references to?
          if (_view == null) _view = new FindReferencesView();
          _view._showView(result);
        }
      }).catchError((_) => _beep());
    } else {
      _beep();
    }
  }

  void _beep() => atom.beep();
}

class FindReferencesView extends AtomView {
  CoreElement status;
  ListTreeBuilder treeBuilder;
  StreamSubscription sub;
  _MatchParser matchParser = new _MatchParser();

  FindReferencesView() : super('References', classes: 'find-references',
      prefName: 'References') {
    status = content.add(div(c: 'search-summary'));
    treeBuilder = content.add(new ListTreeBuilder(_render)..flex());
    treeBuilder.onSelected.listen(_jumpTo);
    treeBuilder.onDoubleClick.listen(_doubleClick);
  }

  void _showView(FindElementReferencesResult findResult) {
    status.text = 'Searching…';
    status.clazz('searching');

    treeBuilder.clear();

    Stream<SearchResult> stream = analysisServer.filterSearchResults(findResult.id);

    stream.toList().then((List<SearchResult> l) {
      status.text = '${commas(l.length)} ${pluralize('result', l.length)} found.';
      status.toggleClass('searching');

      LinkedHashMap<String, List<SearchResult>> results = new LinkedHashMap();
      for (SearchResult r in l) {
        String path = r.location.file;
        if (results[path] == null) results[path] = [];
        results[path].add(r);
      }
      for (String path in results.keys) {
        Node node = new Node(path, canHaveChildren: true);
        results[path].forEach((r) => node.add(new Node(r)));
        treeBuilder.addNode(node);
      }
    });

    show();

    matchParser.reset();
  }

  void _render(item, html.Element intoElement) {
    if (item is String) {
      projectManager.getProjectFor(item);
      List<String> relPath = atom.project.relativizePath(item);
      String path = relPath[1];
      if (relPath[0] != null) {
        String base = relPath[0];
        int index = base.lastIndexOf(separator);
        if (index != -1) base = base.substring(index + 1);
        path = '${base} ${path}';
      }
      html.SpanElement span = new html.SpanElement();
      span.text = path;
      intoElement.children.add(span);
    } else {
      SearchResult result = item;
      intoElement.classes.add('search-result');
      if (result.isPotential) intoElement.classes.add('potential-match');

      int line = result.location.startLine;
      intoElement.children.add(
          new html.SpanElement()..text = '${commas(line)}: '..classes.add('result-line'));

      List<String> match = matchParser.parseMatch(result.location);
      if (match != null) {
        intoElement.children.add(
            new html.SpanElement()..text = match[0]..classes.add('text-subtle'));
        intoElement.children.add(
            new html.SpanElement()..text = match[1]..classes.add('result-exact'));
        intoElement.children.add(
            new html.SpanElement()..text = match[2]..classes.add('text-subtle'));
      }
    }
  }

  void _jumpTo(Node node) {
    if (node.data is SearchResult) {
      editorManager.jumpToLocation((node.data as SearchResult).location);
    }
  }

  void _doubleClick(Node node) {
    if (node.data is String) {
      String path = node.data;
      atom.workspace.open(path, options: { 'searchAllPanes': true });
    }
  }

  void hide() {
    // Cancel any active search.
    if (sub != null) sub.cancel();
    super.hide();
  }
}

class _MatchParser {
  String file;
  List<String> lines;

  List<String> parseMatch(Location l) {
    if (file != l.file) {
      reset();
      _parse(l.file);
    }

    if (lines == null || l.startLine >= lines.length) return null;

    String line = lines[l.startLine - 1];
    int col = l.startColumn - 1;

    String start = line.substring(0, col);
    int max = math.min(l.length, line.length - col);
    String extract = line.substring(col, col + max);
    String end = '';
    if (max < line.length) end = line.substring(col + max);

    start = start.trimLeft();
    end = end.trimRight();

    final int len = 20;

    if (start.length > len) start = '…${start.substring(start.length - len + 2)}';
    if (end.length > len) end = '${end.substring(0, len - 2)}…';

    return [start, extract, end];
  }

  void reset() {
    file = null;
    lines = null;
  }

  void _parse(String path) {
    File f = new File.fromPath(path);
    String contents = f.readSync();
    lines = contents.split('\n');
    file = path;
  }
}
