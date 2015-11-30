library atom.refactor;

import 'dart:async';

import 'package:logging/logging.dart';

import '../analysis/analysis_server_lib.dart'
    show Refactorings, SourceChange, SourceEdit, SourceFileEdit;
import '../analysis_server.dart';
import '../atom.dart';
import '../atom_utils.dart';
import '../editors.dart';
import '../state.dart';
import '../utils.dart';

final Logger _logger = new Logger('refactoring');

class RefactoringHelper implements Disposable {
  Disposables _commands = new Disposables();

  RefactoringHelper() {
    _commands.add(
        atom.commands.add('atom-text-editor', 'dartlang:refactor-rename', (e) {
      _handleRenameRefactor(e.editor);
    }));
  }

  void dispose() => _commands.dispose();

  void _handleRenameRefactor(TextEditor editor) {
    String path = editor.getPath();

    if (projectManager.getProjectFor(path) == null) {
      atom.beep();
      return;
    }

    Range range = editor.getSelectedBufferRange();
    TextBuffer buffer = editor.getBuffer();
    int offset = buffer.characterIndexForPosition(range.start);
    int end = buffer.characterIndexForPosition(range.end);
    String text = editor.getText();
    String oldName = _findIdentifier(text, offset);

    // TODO: Timeout if the refactor request takes too long?
    Job job = new AnalysisRequestJob('rename', () {
      return analysisServer
          .getAvailableRefactorings(path, offset, end - offset)
          .then((AvailableRefactoringsResult result) {
        if (result == null) return;
        _handleAvailableRefactoringsResult(result, path, offset, end, oldName);
      });
    });
    job.schedule();
  }

  // TODO: use the rename refactoring feedback to better select the ID being
  // renamed.

  void _handleAvailableRefactoringsResult(AvailableRefactoringsResult result,
      String path, int offset, int end, String oldName) {
    String newName;
    List refactorings = result.kinds;

    bool canRefactor = refactorings.contains(Refactorings.RENAME);

    if (!canRefactor) {
      atom.beep();
      return null;
    }

    promptUser('Rename refactor: enter the new name.',
        defaultText: oldName, selectText: true).then((_newName) {
      newName = _newName;
      if (_newName == null) return null;

      Job job = new AnalysisRequestJob('rename', () {
        // Perform the refactoring.
        RefactoringOptions option = new RenameRefactoringOptions(newName);
        return analysisServer
            .getRefactoring(
                Refactorings.RENAME, path, offset, end - offset, false,
                options: option)
            .then((RefactoringResult result) {
          if (result == null) return;
          _handleRefactoringResult(result, "Renamed '${oldName}' to '${newName}'.", path);
        });
      });
      job.schedule();
    });
  }

  void _handleRefactoringResult(
      RefactoringResult result, String successMsg, String path) {
    // TODO: use optionsProblems
    // TODO: use finalProblems
    // TODO: use feedback
    if (result.initialProblems.isNotEmpty) {
      atom.notifications.addError('Unable to Refactor',
          detail: '${result.initialProblems.first.message}');
      atom.beep();
      return;
    }

    SourceChange change = result.change;
    if (change == null) {
      atom.notifications.addError('Unable to Refactor',
          detail: 'No change information returned.');
      atom.beep();
      return;
    }

    // Remove any 'potential' edits. The analysis server sends over things
    // like edits to package: files.
    List<SourceFileEdit> sourceFileEdits = change.edits;
    sourceFileEdits.forEach((SourceFileEdit fileEdit) {
      fileEdit.edits.removeWhere((SourceEdit edit) => edit.id != null);
    });
    sourceFileEdits
        .removeWhere((SourceFileEdit fileEdit) => fileEdit.edits.isEmpty);

    var apply = () {
      _applyEdits(sourceFileEdits, successMsg)
          .then((_) {
        // Ensure the original file is selected.
        atom.workspace.open(path);
      });
    };

    // If this changes a single file,
    // then apply the change without confirming with the user
    if (sourceFileEdits.length == 1) {
      apply();
      return;
    }

    // Otherwise, confirm this refactoring with users
    // since it will affect multiple files.
    var project = projectManager.getProjectFor(path);
    String projectPrefix = project == null ? '' : project.path;

    Iterable<String> paths = sourceFileEdits.map((edit) {
      String filePath = edit.file;
      if (filePath.startsWith(projectPrefix)) {
        return project.name + filePath.substring(projectPrefix.length);
      } else {
        return filePath;
      }
    });
    String fileSummary = (paths.toList()..sort()).join('\n');
    Notification notification;

    var userConfirmed = () {
      notification.dismiss();
      apply();
    };

    var userCancelled = () => notification.dismiss();

    notification = atom.notifications
        .addInfo('Refactor ${sourceFileEdits.length} files?',
            detail: fileSummary,
            dismissable: true,
            buttons: [
              new NotificationButton('Continue', userConfirmed),
              new NotificationButton('Cancel', userCancelled)
            ]);
  }

  /// Apply the source edits, displaying [successMsg] once complete.
  Future _applyEdits(List<SourceFileEdit> sourceFileEdits, String successMsg) {
    return Future.forEach(sourceFileEdits, (SourceFileEdit edit) {
      return atom.workspace.open(edit.file, options: {'searchAllPanes': true})
          .then((TextEditor editor) {
        applyEdits(editor, edit.edits);
      });
    }).then((_) {
      String fileSummary = sourceFileEdits.map((edit) => edit.file).join('\n');
      if (sourceFileEdits.length == 1) fileSummary = null;
      atom.notifications.addSuccess(successMsg, detail: fileSummary);
    }).catchError((e) {
      atom.notifications.addError('Refactoring Error', detail: '${e}');
    });
  }

  /// Find the identifier at the given [offset] location.
  static String _findIdentifier(String text, int offset) {
    while (offset > 0) {
      if (idRegex.hasMatch(text[offset - 1])) {
        offset--;
      } else {
        break;
      }
    }

    StringBuffer buf = new StringBuffer();

    while (offset < text.length) {
      String c = text[offset];

      if (idRegex.hasMatch(c)) {
        buf.write(c);
        offset++;
      } else {
        break;
      }
    }

    return buf.toString();
  }
}
