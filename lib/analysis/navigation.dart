
library atom.navigation;

import 'dart:async';
import 'dart:js';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../editors.dart';
import '../state.dart';
import '../utils.dart';
import 'analysis_server_gen.dart';

final Logger _logger = new Logger('navigation');

// TODO: Switch over to something link nuclide-click-to-symbol when that's
// available as a platform API.

// TODO: use shift-F3 to navigate back?

class NavigationHelper implements Disposable {
  Disposable _commandDisposable;
  AnalysisNavigation _lastNavInfo;
  Map<String, Completer> _navCompleters = {};
  Set<String> _listening = new Set();

  NavigationHelper() {
    _commandDisposable = atom.commands.add('atom-text-editor',
        'dart-lang-experimental:jump-to-declaration', _handleNavigate);
    analysisServer.onNavigaton.listen(_navigationEvent);
    editorManager.dartProjectEditors.onActiveEditorChanged.listen(_activate);
    _activate(editorManager.dartProjectEditors.activeEditor);
  }

  void dispose() => _commandDisposable.dispose();

  void _activate(TextEditor editor) {
    if (editor == null) return;

    String path = editor.getPath();
    if (_listening.contains(path)) return;
    _listening.add(path);
    editor.onDidDestroy.listen((_) => _listening.remove(path));

    // This view is an HtmlElement, but I can't use it as one. I have to access
    // it through JS interop.
    var view = atom.views.getView(editor.obj);
    var fn = (e) {
      try {
        JsObject evt = new JsObject.fromBrowserObject(e);
        if (evt['altKey']) Timer.run(() => _handleNavigateEditor(editor));
      } catch (e) { }
    };
    view.callMethod('addEventListener', ['click', fn]);
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
          Map options = {
            'initialLine': target.startLine - 1,
            'initialColumn': target.startColumn - 1,
            'searchAllPanes': true
          };

          return atom.workspace.open(file, options).then((TextEditor editor) {
            editor.selectRight(target.length);
          });
        });
      }
    }

    return new Future.error('no element');
  }
}

// class _EventDisposable implements Disposable {
//   final JsObject obj;
//   final fn;
//
//   _EventDisposable(this.obj, this.fn);
//
//   void dispose() {
//     try {
//       obj.callMethod('removeEventListener', ['click', fn]);
//     } catch (e) {
//       print(e);
//     }
//   }
// }
