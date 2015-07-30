
library atom.declaration_nav;

import 'dart:async';
import 'dart:js';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../editors.dart';
import '../js.dart';
import '../state.dart';
import '../utils.dart';
import 'analysis_server_gen.dart';

final Logger _logger = new Logger('declaration_nav');

// TODO: Switch over to something link nuclide-click-to-symbol when that's
// available as a platform API.

class NavigationHelper implements Disposable {
  Disposables _commands = new Disposables();
  AnalysisNavigation _lastNavInfo;
  Map<String, Completer> _navCompleters = {};
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

  void dispose() => _commands.dispose();

  void _activate(TextEditor editor) {
    _eventListener.dispose();

    if (editor == null) return;

    // This view is an HtmlElement, but I can't use it as one. I have to access
    // it through JS interop.
    var view = editor.view;
    var fn = (JsObject evt) {
      try {
        // TODO: Consider using the `hyperclick` package - once atom has package
        // dependencies - and deferring to their keybinding settings.
        bool jump = false;
        if (isMac) {
          // TODO: This does override multiple cursors (cmd-click) on the mac,
          // which might not be desired by some users.
          jump = evt['altKey'] || evt['metaKey'];
        } else {
          jump = evt['ctrlKey '] || evt['altKey'];
        }
        if (jump) Timer.run(() => _handleNavigateEditor(editor));
      } catch (e) { }
    };

    _eventListener = new EventListener(view, 'click', fn);
  }

  void _navigationEvent(AnalysisNavigation navInfo) {
    String path = navInfo.file;
    _lastNavInfo = navInfo;
    if (_navCompleters[path] != null) _navCompleters[path].complete(navInfo);
  }

  void _handleNavigate(AtomEvent event) {
    _handleNavigateEditor(event.editor);
  }

  void _handleNavigateEditor(TextEditor editor) {
    if (analysisServer.isActive) {
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

  Future<AnalysisNavigation> _getNavigationInfoFor(String path) {
    if (_lastNavInfo != null && _lastNavInfo.file == path) {
      return new Future.value(_lastNavInfo);
    }

    if (_navCompleters[path] != null) return _navCompleters[path].future;

    Completer completer = new Completer();
    _navCompleters[path] = completer;
    new Timer(new Duration(milliseconds: 350), () {
      if (!completer.isCompleted) completer.complete(null);
    });
    completer.future.whenComplete(() => _navCompleters.remove(path));
    return completer.future;
  }

  static Future _processNavInfo(TextEditor editor, int offset,
      AnalysisNavigation navInfo) {
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
          navigationManager.navigate(file,
              target.startLine - 1, target.startColumn - 1, target.length);
        });
      }
    }

    return new Future.error('no element');
  }
}
