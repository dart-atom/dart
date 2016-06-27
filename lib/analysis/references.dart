
library atom.references;

import 'dart:async';
import 'dart:collection';
import 'dart:html' as html show Element, SpanElement;
import 'dart:math' as math;

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';
import 'package:logging/logging.dart';

import '../analysis_server.dart';
import '../elements.dart';
import '../state.dart';
import '../views.dart';
import 'analysis_server_lib.dart';

final Logger _logger = new Logger('references');

class FindReferencesHelper implements Disposable {
  Disposable _command;

  FindReferencesHelper() {
    _command = atom.commands.add(
      'atom-text-editor', 'dartlang:find-references', _handleReferences
    );
  }

  void dispose() => _command.dispose();

  void _handleReferences(AtomEvent event) => _handleReferencesEditor(event.editor);

  void _handleReferencesEditor(TextEditor editor) {
    String path = editor.getPath();
    Range range = editor.getSelectedBufferRange();
    int offset = editor.getBuffer().characterIndexForPosition(range.start);

    Job job = new AnalysisRequestJob('find references', () {
      return analysisServer.findElementReferences(path, offset, false).then(
          (FindElementReferencesResult result) {
        if (result == null || result.id == null) {
          atom.beep();
          return;
        } else {
          bool isMethod = result.element.parameters != null;
          String name = "${result.element.name}${isMethod ? '()' : ''}";
          Future<List<SearchResult>> resultsFuture = analysisServer.getSearchResults(result.id);
          FindReferencesView.showView(
            new ReferencesSearch('References', name, resultsFuture: resultsFuture),
            refData: { 'path': path, 'offset': offset }
          );
        }
      });
    });
    job.schedule();
  }
}

class ReferencesSearch {
  final String searchType;
  final String label;

  final List<SearchResult> results;
  final Future<List<SearchResult>> resultsFuture;

  ReferencesSearch(this.searchType, this.label, {this.results, this.resultsFuture});
}

class FindReferencesView extends View {
  static void showView(ReferencesSearch search, { Map refData }) {
    FindReferencesView view = viewGroupManager.getViewById('findReferences');

    if (view != null) {
      view._handleSearchResults(search, refData: refData);
      viewGroupManager.activate(view);
    } else {
      FindReferencesView view = new FindReferencesView();
      view._handleSearchResults(search, refData: refData);
      viewGroupManager.addView('right', view);
    }
  }

  CoreElement title;
  CoreElement subtitle;
  ListTreeBuilder treeBuilder;
  Disposables disposables = new Disposables();
  _MatchParser matchParser = new _MatchParser();

  FindReferencesView() {
    content.toggleClass('find-references');
    content.toggleClass('tab-scrollable-container');
    content.add([
      div(c: 'view-header view-header-static')..add([
        title = div(c: 'view-title'),
        subtitle = div(c: 'view-subtitle')
      ]),
      treeBuilder = new ListTreeBuilder(_render)
    ]);

    treeBuilder.toggleClass('tab-scrollable');
    treeBuilder.onClickNode.listen(_jumpTo);
    treeBuilder.onDoubleClick.listen(_doubleClick);

    disposables.add(new DoubleCancelCommand(handleClose));
  }

  String get id => 'findReferences';

  String get label => 'References';

  void dispose() => disposables.dispose();

  Future _handleSearchResults(ReferencesSearch search, {Map refData}) async {
    title.text = search.searchType;
    subtitle.text = "'${search.label}'; searching…";
    subtitle.toggleClass('searching', true);

    treeBuilder.clear();

    List<SearchResult> resultsList;

    if (search.results != null) {
      resultsList = search.results;
    } else {
      resultsList = await search.resultsFuture;
    }

    subtitle.text = "${commas(resultsList.length)} ${pluralize('result', resultsList.length)} "
      "for '${search.label}'";
    subtitle.toggleClass('searching', false);

    LinkedHashMap<String, List<SearchResult>> results = new LinkedHashMap();

    for (SearchResult r in resultsList) {
      String path = r.location.file;
      if (results[path] == null) results[path] = [];
      results[path].add(r);
    }

    for (String path in results.keys) {
      Node node = new Node(path, canHaveChildren: true);
      List<SearchResult> fileResults = results[path];
      fileResults.sort((SearchResult a, SearchResult b) {
        return a.location.offset - b.location.offset;
      });
      fileResults.forEach((r) => node.add(new Node(r)));
      treeBuilder.addNode(node);
    }

    matchParser.reset();
  }

  void _render(item, html.Element intoElement) {
    if (item is String) {
      List<String> items = _renderPath(item);
      html.SpanElement span = new html.SpanElement();
      span.text = items.join(' ');
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
        intoElement.children.add(new html.SpanElement()..text = match[1]);
        intoElement.children.add(
            new html.SpanElement()..text = match[2]..classes.add('text-subtle'));
      }
    }
  }

  void _jumpTo(Node node) {
    if (node.data is SearchResult) {
      treeBuilder.selectNode(node);

      Location l = (node.data as SearchResult).location;
      editorManager.jumpToLocation(l.file,
          l.startLine - 1, l.startColumn - 1, l.length);
    }
  }

  void _doubleClick(Node node) {
    if (node.data is String) {
      String path = node.data;
      atom.workspace.openPending(path, options: { 'searchAllPanes': true });
    }
  }

  List<String> _renderPath(String originalPath) {
    // Check for project files.
    List<String> relPath = atom.project.relativizePath(originalPath);
    if (relPath[0] != null) {
      String base = relPath[0];
      int index = base.lastIndexOf(fs.separator);
      if (index != -1) base = base.substring(index + 1);
      return [base, relPath[1]];
    }

    // Check for package files.
    if (originalPath.contains(_cachePrefix)) {
      int index = originalPath.indexOf(_cachePrefix);
      String path = originalPath.substring(index + _cachePrefix.length);
      if (path.startsWith(_pubPrefix)) path = path.substring(_pubPrefix.length);
      return ['Package', path];
    }

    // Check for SDK files.
    var sdk = sdkManager.sdk;
    if (sdk != null) {
      String prefix = sdk.path;
      if (originalPath.startsWith(prefix)) {
        String path = originalPath.substring(prefix.length);
        if (path.startsWith(_libPrefix)) path = path.substring(_libPrefix.length);
        return ['SDK', path];
      }
    }

    // Return the original path.
    return [originalPath];
  }

  static final _cachePrefix = '${fs.separator}.pub-cache${fs.separator}';
  static final _pubPrefix = 'hosted${fs.separator}pub.dartlang.org${fs.separator}';
  static final _libPrefix = '${fs.separator}lib${fs.separator}';
}

class _MatchParser {
  String file;
  List<String> lines;

  List<String> parseMatch(Location l) {
    if (file != l.file) {
      reset();
      _parse(l.file);
    }

    if (lines == null || l.startLine <= 0 || l.startLine >= lines.length) return null;

    String line = lines[l.startLine - 1];

    try {
      int col = l.startColumn - 1;
      col = math.min(col, line.length);

      String start = line.substring(0, col);
      int max = math.min(l.length, line.length - col);
      String extract = line.substring(col, col + max);
      String end = '';
      if (max < line.length) end = line.substring(col + max);

      start = start.trimLeft();
      end = end.trimRight();

      final int llen = 20;
      final int rlen = 30;

      if (start.length > llen) start = '…${start.substring(start.length - llen + 2)}';
      if (end.length > rlen) end = '${end.substring(0, rlen - 2)}…';

      return [start, extract, end];
    } catch (e) {
      if (line.length > 60) line = line.substring(0, 60);
      return [line, '', ''];
    }
  }

  void reset() {
    file = null;
    lines = null;
  }

  void _parse(String path) {
    this.file = path;

    // Handle files that are open + modified in atom.
    for (TextEditor editor in atom.workspace.getTextEditors()) {
      if (editor.getPath() == path) {
        String contents = editor.getText();
        lines = contents.split('\n');
        return;
      }
    }

    try {
      String contents = new File.fromPath(path).readSync();
      lines = contents == null ? [] : contents.split('\n');
    } catch (e) {
      lines = [];
    }
  }
}
