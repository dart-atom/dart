library buffer.updater;

import '../atom.dart';
import '../analysis/analysis_server_gen.dart';
import '../state.dart';
import '../utils.dart';

class BufferUpdaterManager implements Disposable {
  List<BufferUpdater> updaters = [];

  BufferUpdaterManager() {
    analysisServer.isActiveProperty.listen((active) {
      updaters.forEach((BufferUpdater updater) => updater.serverActive(active));
    });
    editorManager.dartProjectEditors.openEditors.forEach(_newEditor);
    editorManager.dartProjectEditors.onEditorOpened.listen(_newEditor);
  }

  void _newEditor(TextEditor editor) {
    updaters.add(new BufferUpdater(this, editor));
  }

  void dispose() {
    updaters.toList().forEach((BufferUpdater updater) => updater.dispose());
    updaters.clear();
  }

  remove(BufferUpdater updater) => updaters.remove(updater);
}

/// Observe a TextEditor and notifies the analysis_server of any content changes
/// it should care about.
///
/// Although this class should use the "ChangeContentOverlay" route,
/// Atom doesn't provide us with diffs, so it is more expensive to calculate
/// the diffs than just remove the existing overlay and add a new one with
/// the changed content.
class BufferUpdater extends Disposables {
  final BufferUpdaterManager manager;
  final TextEditor editor;

  final StreamSubscriptions _subs = new StreamSubscriptions();

  String lastSent;

  BufferUpdater(this.manager, this.editor) {
    _subs.add(editor.onDidChange.listen(_didChange));
    _subs.add(editor.onDidDestroy.listen(_didDestroy));
    addOverlay();
  }

  Server get server => analysisServer.server;

  void serverActive(bool active) {
    if (active) {
      addOverlay();
    } else {
      lastSent = null;
    }
  }

  void _didChange([_]) {
    changedOverlay();
  }

  void _didDestroy([_]) {
    dispose();
  }

  addOverlay() {
    if (analysisServer.isActive) {
      lastSent = editor.getText();
      server.analysis.updateContent({
        editor.getPath(): new AddContentOverlay('add', lastSent)
      });
    }
  }

  changedOverlay() {
    if (analysisServer.isActive) {
      if (lastSent == null) {
        addOverlay();
      } else {
        String contents = editor.getText();

        // TODO: See #31.
        // List<Edit> edits = simpleDiff(lastSent, contents);
        // int count = 1;
        // List<SourceEdit> diffs = edits.map((edit) => new SourceEdit(
        //     edit.offset, edit.length, edit.replacement, id: '${count++}')).toList();
        // var overlay = new ChangeContentOverlay('change', diffs);
        // server.analysis.updateContent({ editor.getPath(): overlay });
        server.analysis.updateContent({
          editor.getPath(): new RemoveContentOverlay('remove')
        });
        server.analysis.updateContent({
          editor.getPath(): new AddContentOverlay('add', contents)
        });

        lastSent = contents;
      }
    }
  }

  removeOverlay() {
    if (analysisServer.isActive) {
      server.analysis.updateContent({
        editor.getPath(): new RemoveContentOverlay('remove')
      });
    }

    lastSent = null;
  }

  dispose() {
    removeOverlay();
    super.dispose();
    _subs.cancel();
    manager.remove(this);
  }
}
