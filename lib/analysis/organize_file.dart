library atom.analysis.organize_file;

import '../analysis_server.dart';
import '../atom.dart';
import '../editors.dart';
import '../state.dart';
import '../utils.dart';

// TODO: Run in an AnalysisRequestJob job.

class OrganizeFileManager implements Disposable {
  Disposables disposables = new Disposables();

  OrganizeFileManager() {
    _addEditorCommand('dartlang:sort-members', _handleSortMembers);
    _addEditorCommand('dartlang:organize-directives', _handleOrganizeDirectives);
  }

  void _addEditorCommand(String command, void impl(TextEditor editor)) {
    disposables.add(atom.commands.add('atom-text-editor', command, (e) {
      if (!analysisServer.isActive) {
        atom.beep();
        return;
      }

      TextEditor editor = e.editor;

      if (projectManager.getProjectFor(editor.getPath()) == null) {
        atom.beep();
        return;
      }

      impl(editor);
    }));
  }

  void dispose() => disposables.dispose();

  void _handleSortMembers(TextEditor editor) {
    String path = editor.getPath();
    /*Future f =*/ analysisServer.server.edit.sortMembers(path).then((result) {
      SourceFileEdit edit = result.edit;

      if (edit.edits.isEmpty) {
        atom.notifications.addSuccess('No changes from sort members.');
      } else {
        atom.notifications.addSuccess('Sort members successful.');
        applyEdits(editor, edit.edits);
      }
    });

    // TODO: Run the operation in a job to give the user some feedback for
    // longer running operations. Also, handle error results.
    //analysisServer.handleResultTimeout('sort members');
  }

  void _handleOrganizeDirectives(TextEditor editor) {
    String path = editor.getPath();

    analysisServer.server.edit.organizeDirectives(path).then((result) {
      SourceFileEdit edit = result.edit;

      if (edit.edits.isEmpty) {
        atom.notifications.addSuccess('No changes from organize directives.');
      } else {
        atom.notifications.addSuccess('Organize directives successful.');
        applyEdits(editor, edit.edits);
      }
    }).catchError((e) {
      if (e is RequestError && e.code == 'UNKNOWN_REQUEST') {
        atom.notifications.addWarning(
            'Organize directives is not supported in this version of the analysis server.');
      } else {
        atom.notifications
            .addError('Error running organize directives.', detail: '${e}');
      }
    });
  }
}
