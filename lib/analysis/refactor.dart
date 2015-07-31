
library atom.refactor;

import 'dart:async';

import 'package:logging/logging.dart';

import '../analysis_server.dart';
import '../analysis/analysis_server_gen.dart' show SourceChange, SourceFileEdit;
import '../atom.dart';
import '../atom_utils.dart';
import '../editors.dart';
import '../state.dart';
import '../utils.dart';

final Logger _logger = new Logger('refactoring');

class RefactoringHelper implements Disposable {
  Disposables _commands = new Disposables();

  RefactoringHelper() {
    _commands.add(atom.commands.add('atom-text-editor', 'dartlang:refactor-rename', (e) {
      _handleRenameRefactor(e.editor);
    }));
  }

  void dispose() => _commands.dispose();

  void _handleRenameRefactor(TextEditor editor) {
    if (!analysisServer.isActive) {
      atom.beep();
      return;
    }

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
    String newName;

    // TODO: Timeout if the refactor request takes too long?
    analysisServer.getAvailableRefactorings(path, offset, end - offset).then(
        (AvailableRefactoringsResult result) {
      List refactorings = result.kinds;

      bool canRefactor = refactorings.contains('RENAME');

      if (!canRefactor) {
        atom.beep();
        return null;
      }

      return promptUser('Rename refactor: enter the new name.',
          defaultText: oldName,
          selectText: true);
    }).then((_newName) {
      newName = _newName;

      if (newName != null) {
        // Perform the refactoring.
        RefactoringOptions option = new RenameRefactoringOptions(newName);
        return analysisServer.getRefactoring(
            'RENAME', path, offset, end - offset, false, options: option);
      }
    }).then((RefactoringResult result) {
      if (result != null) {
        if (result.initialProblems.isNotEmpty) {
          atom.notifications.addError('Unable to Perform Rename',
              detail: '${result.initialProblems.first.message}');
          atom.beep();
        } else if (result.change == null) {
          atom.notifications.addError('Unable to Perform Rename',
              detail: 'No change information returned.');
          atom.beep();
        } else {
          SourceChange change = result.change;
          List<SourceFileEdit> sourceFileEdits = change.edits;

          // We want to confirm this refactoring with users if it's going to
          // rename across files.
          if (sourceFileEdits.length > 1) {
            String fileSummary = sourceFileEdits.map((edit) => edit.file).join('\n');
            var val = atom.confirm('Confirm rename in ${sourceFileEdits.length} files?',
                detailedMessage: fileSummary,
                buttons: ['Rename', 'Cancel']);
            if (val != 0) return;
          }

          _apply(sourceFileEdits, oldName, newName);
        }
      }
    });
  }

  void _apply(List<SourceFileEdit> sourceFileEdits, String oldName, String newName) {
    Future.forEach(sourceFileEdits, (SourceFileEdit edit) {
      return atom.workspace.open(edit.file, options: {'searchAllPanes': true}).then(
          (TextEditor editor) {
        applyEdits(editor, edit.edits);
      });
    }).then((_) {
      String fileSummary = sourceFileEdits.map((edit) => edit.file).join('\n');
      if (sourceFileEdits.length == 1) fileSummary = null;
      atom.notifications.addSuccess("Renamed '${oldName}' to '${newName}'.",
          detail: fileSummary);
    }).catchError((e) {
      atom.notifications.addError('Error Performing Rename', detail: '${e}');
    });
  }

  static RegExp _idRegex = new RegExp(r'[_a-zA-Z0-9]');

  static String _findIdentifier(String text, int offset) {
    while (offset > 0) {
      if (_idRegex.hasMatch(text[offset - 1])) {
        offset--;
      } else {
        break;
      }
    }

    StringBuffer buf = new StringBuffer();

    while (offset < text.length) {
      String c = text[offset];

      if (_idRegex.hasMatch(c)) {
        buf.write(c);
        offset++;
      } else {
        break;
      }
    }

    return buf.toString();
  }
}
