library atom.analysis.organize_file;

import 'package:atom/atom.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';

import '../analysis_server.dart';
import '../editors.dart';
import '../state.dart';

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

    AnalysisRequestJob job = new AnalysisRequestJob('Sort members', () {
      return analysisServer.server.edit.sortMembers(path).then((result) {
        SourceFileEdit edit = result.edit;

        if (edit.edits.isEmpty) {
          atom.notifications.addSuccess('No changes from sort members.');
        } else {
          atom.notifications.addSuccess('Sort members successful.');
          applyEdits(editor, edit.edits);
        }
      });
    });

    job.schedule();
  }

  void _handleOrganizeDirectives(TextEditor editor) {
    String path = editor.getPath();

    AnalysisRequestJob job = new AnalysisRequestJob('Organize directives', () {
      return analysisServer.server.edit.organizeDirectives(path).then((result) {
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
    });

    job.schedule();
  }
}
