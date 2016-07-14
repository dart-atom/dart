
library atom.declaration_nav;

import 'dart:async';
import 'dart:js';

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/process.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../editors.dart';
import '../state.dart';
import '../usage.dart' show trackCommand;
import 'analysis_server_lib.dart';

final Logger _logger = new Logger('declaration_nav');

final String _keyPref = '${pluginId}.jumpToDeclarationKeys';

// TODO: Use analysisServer.getNavigation()?

class NavigationHelper implements Disposable {
  Disposables _commands = new Disposables();
  _NavCompleterHelper _completerHelper = new _NavCompleterHelper();
  Disposable _eventListener = new Disposables();

  NavigationHelper() {
    _commands.add(atom.commands.add('atom-text-editor',
        'dartlang:jump-to-declaration', _handleNavigate));
    _commands.add(atom.commands.add('atom-text-editor[data-grammar~="dart"]',
        'symbols-view:go-to-declaration', _handleNavigate));

    analysisServer.onNavigaton.listen(_navigationEvent);
    editorManager.dartProjectEditors.onActiveEditorChanged.listen(_activate);
    _activate(editorManager.dartProjectEditors.activeEditor);
  }

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

        return flashSelection(editor, sourceRange).then((_) {
          // TODO(devoncarew): Check for target.startLine == 0, target.startColumn,
          // target.offset != 0, and parse the indicated file.

          navigationManager.jumpToLocation(file,
              target.startLine - 1, target.startColumn - 1, target.length);
        });
      }
    }

    return new Future.error('no element');
  }

  void dispose() => _commands.dispose();
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
