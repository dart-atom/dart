library buffer.updater;

import '../atom.dart';
import '../analysis/analysis_server_gen.dart';
import '../state.dart';
import '../utils.dart';

Disposable observeBuffersForAnalysisServer() {
  Disposables disposables = new Disposables();
  disposables.add(atom.workspace.observeTextEditors((editor) {
    disposables.add(editor.observeGrammar((_) {
      if (!_acceptableGrammar(editor)) return;
      if (editor.getPath() == null) return;

      var bufferUpdater = new BufferUpdater(editor);
      bufferUpdater.observe();
    }));
  }));
  return disposables;
}

_acceptableGrammar(editor) {
  var grammar = editor.getRootScopeDescriptor();
  var scopes  = grammar['scopes'];
  return scopes.contains('source.dart');
}

/// Observe a TextEditor and notifies the analysis_server of any content changes
/// it should care about.
///
/// Although this class should use the "ChangeContentOverlay" route,
/// Atom doesn't provide us with diffs, so it is more expensive to calculate
/// the diffs than just remove the existing overlay and add a new one with
/// the changed content.
class BufferUpdater extends Disposables {
  final TextEditor _editor;
  final StreamSubscriptions _subs = new StreamSubscriptions();

  BufferUpdater(this._editor);

  Server get server => analysisServer.server;

  observe() {
    _subs.add(_editor.onDidSave.listen((_) {
      // https://github.com/dart-lang/sdk/issues/23579
      if (_acceptableGrammar(_editor)) {
        removeOverlay(_editor);
      }
    }));

    _subs.add(_editor.onDidChange.listen((_) {
      if (_acceptableGrammar(_editor) && _editor.isModified()) {
        // https://github.com/dart-lang/sdk/issues/23577
        removeOverlay(_editor);
        addOverlay(_editor);
      }
    }));

    _subs.add(_editor.onDidDestroy.listen((_) => this.dispose()));
  }

  addOverlay(TextEditor editor) {
    // ...?!
    var addOverlay = new AddContentOverlay('add', editor.getText());
    server.analysis.updateContent({
      editor.getPath(): addOverlay
    });
  }

  removeOverlay(TextEditor editor) {
    // ...?!
    var removeOverlay = new RemoveContentOverlay('remove');
    server.analysis.updateContent({
      editor.getPath(): removeOverlay
    });
  }

  dispose() {
    super.dispose();
    _subs.cancel();
  }
}
