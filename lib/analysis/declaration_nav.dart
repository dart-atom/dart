
library atom.declaration_nav;

import 'dart:async';
import 'dart:js';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../editors.dart';
import '../js.dart';
import '../state.dart';
import '../usage.dart' show trackCommand;
import '../utils.dart';
import 'analysis_server_lib.dart';

final Logger _logger = new Logger('declaration_nav');

final String _keyPref = '${pluginId}.jumpToDeclarationKeys';

// TODO: Use analysisServer.getNavigation()?

class NavigationHelper implements Disposable {
  Disposables _commands = new Disposables();
  _NavCompleterHelper _completerHelper = new _NavCompleterHelper();
  Disposable _eventListener = new Disposables();

  List<_NavigationPosition> _history = [];

  NavigationHelper() {
    _commands.add(atom.commands.add('atom-text-editor',
        'dartlang:jump-to-declaration', _handleNavigate));
    _commands.add(atom.commands.add('atom-text-editor',
        'dartlang:return-from-declaration', _handleNavigateReturn));

    _commands.add(atom.commands.add('atom-text-editor[data-grammar~="dart"]',
        'symbols-view:go-to-declaration', _handleNavigate));
    _commands.add(atom.commands.add('atom-text-editor[data-grammar~="dart"]',
        'symbols-view:return-from-declaration', _handleNavigateReturn));

    analysisServer.onNavigaton.listen(_navigationEvent);
    editorManager.dartProjectEditors.onActiveEditorChanged.listen(_activate);
    _activate(editorManager.dartProjectEditors.activeEditor);
  }

  void dispose() => _commands.dispose();

  void _activate(TextEditor editor) {
    _eventListener.dispose();

    if (editor == null) return;

    // This view is an HtmlElement, but I can't use it as one. I have to access
    // it through JS interop.
    var view = editor.view;
    var fn = (JsObject evt) {
      try {
        bool shouldJump = evt[_jumpKey()];
        if (shouldJump) {
          _handleNavigateEditor(editor);
        }
      } catch (e) { }
    };

    _eventListener = new EventListener(view, 'mousedown', fn);
  }

  static String _jumpKey() {
    String key = atom.config.getValue(_keyPref);
    if (key == 'command') return 'metaKey';
    if (key == 'control') return 'ctrlKey';
    if (key == 'option' || key == 'alt') return 'altKey';
    return isMac ? 'metaKey' : 'ctrlKey';
  }

  void _navigationEvent(AnalysisNavigation navInfo) {
    _completerHelper.handleNavInfo(navInfo);
  }

  void _handleNavigate(AtomEvent event) {
    _handleNavigateEditor(event.editor);
  }

  void _handleNavigateEditor(TextEditor editor) {
    if (analysisServer.isActive) {
      trackCommand('jump-to-declaration');

      String path = editor.getPath();
      Range range = editor.getSelectedBufferRange();
      int offset = editor.getBuffer().characterIndexForPosition(range.start);

      _getNavigationInfoFor(path).then((AnalysisNavigation navInfo) {
        if (navInfo != null) {
          return _processNavInfo(editor, offset, navInfo);
        } else {
          _beep();
        }
      }).catchError((_) => _beep());
    } else {
      _beep();
    }
  }

  void _handleNavigateReturn(AtomEvent _) {
    trackCommand('return-from-declaration');

    if (_history.isEmpty) {
      _beep();
      _logger.info('No navigation positions on the stack.');
    } else {
      _NavigationPosition pos = _history.removeLast();
      editorManager.jumpToLocation(pos.path, pos.line, pos.column, pos.length);
    }
  }

  void _beep() => atom.beep();

  static final Duration _timeout = new Duration(milliseconds: 1000);

  Future<AnalysisNavigation> _getNavigationInfoFor(String path) {
    return _completerHelper.getNavigationInfo(path, timeout: _timeout);
  }

  Future _processNavInfo(TextEditor editor, int offset, AnalysisNavigation navInfo) {
    List<String> files = navInfo.files;
    List<NavigationTarget> targets = navInfo.targets;
    List<NavigationRegion> regions = navInfo.regions;

    for (NavigationRegion region in regions) {
      if (region.offset <= offset && (region.offset + region.length > offset)) {
        NavigationTarget target = targets[region.targets.first];
        String file = files[target.fileIndex];
        TextBuffer buffer = editor.getBuffer();
        Range sourceRange = new Range.fromPoints(
            buffer.positionForCharacterIndex(region.offset),
            buffer.positionForCharacterIndex(region.offset + region.length));

        _pushCurrentLocation();

        return flashSelection(editor, sourceRange).then((_) {
          editorManager.jumpToLocation(file,
              target.startLine - 1, target.startColumn - 1, target.length);
        });
      }
    }

    return new Future.error('no element');
  }

  void _pushCurrentLocation() {
    TextEditor editor = atom.workspace.getActiveTextEditor();

    if (editor != null) {
      Range range = editor.getSelectedBufferRange();
      if (range == null) return;

      int length = range.isSingleLine() ? range.end.column - range.start.column : null;
      if (length == 0) length = null;

      Point start = range.start;
      _history.add(
          new _NavigationPosition(editor.getPath(), start.row, start.column, length));
    }
  }
}

class _NavCompleterHelper {
  List<AnalysisNavigation> _lastInfos = [];
  Map<String, Completer<AnalysisNavigation>> _completers = {};

  _NavCompleterHelper();

  void handleNavInfo(AnalysisNavigation info) {
    String path = info.file;

    if (_completers[path] != null) {
      _completers[path].complete(info);
      _completers.remove(path);
    }

    _lastInfos.removeWhere((nav) => nav.file == path);
    _lastInfos.insert(0, info);
    if (_lastInfos.length > 24) _lastInfos = _lastInfos.sublist(0, 24);
  }

  Future<AnalysisNavigation> getNavigationInfo(String path, {Duration timeout}) {
    for (AnalysisNavigation nav in _lastInfos) {
      if (nav.file == path) {
        return new Future.value(nav);
      }
    }

    if (_completers[path] == null) {
      _completers[path] = new Completer<AnalysisNavigation>();
    }

    if (timeout != null) {
      return _completers[path].future.timeout(timeout, onTimeout: () => null);
    } else {
      return _completers[path].future;
    }
  }
}

class _NavigationPosition {
  final String path;
  final int line;
  final int column;
  final int length;

  _NavigationPosition(this.path, this.line, this.column, [this.length]);

  String toString() => '[${path} ${line}:${column}]';
}
