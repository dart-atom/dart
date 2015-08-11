library atom.analysis.organize_file;

import '../analysis_server.dart';
import '../atom.dart';
import '../editors.dart';
import '../state.dart';
import '../utils.dart';

class OrganizeFileManager implements Disposable {
  Disposables disposables = new Disposables();

  OrganizeFileManager() {
    disposables.add(atom.commands.add('atom-text-editor', 'dartlang:sort-members', (e) {
      _handleSortMembers(e.editor);
    }));
  }

  void dispose() => disposables.dispose();

  void _handleSortMembers(TextEditor editor) {
    if (!analysisServer.isActive) {
      atom.beep();
      return;
    }

    String path = editor.getPath();

    if (projectManager.getProjectFor(path) == null) {
      atom.beep();
      return;
    }

    analysisServer.server.edit.sortMembers(path).then((result) {
      SourceFileEdit edit = result.edit;

      if (edit.edits.isEmpty) {
        atom.notifications.addSuccess('No changes from sort members.');
      } else {
        atom.notifications.addSuccess('Sort members successful.');
        applyEdits(editor, edit.edits);
      }
    });
  }
}
