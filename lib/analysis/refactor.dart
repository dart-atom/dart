library atom.refactor;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';
import 'package:logging/logging.dart';

import '../analysis/analysis_server_lib.dart' show
    Refactorings, SourceChange, SourceEdit, SourceFileEdit,
    RenameRefactoringOptions, ExtractLocalVariableRefactoringOptions;
import '../analysis_server.dart';
import '../editors.dart';
import '../state.dart';

final Logger _logger = new Logger('refactoring');

typedef _RefactorHandler(String path, int offset, int end, String text);

class RefactoringHelper implements Disposable {
  Disposables _commands = new Disposables();

  RefactoringHelper() {
    _addCommand('dartlang:refactor-extract-local', _handleExtractLocal);
    _addCommand('dartlang:refactor-inline-local', _handleInlineLocal);
    _addCommand('dartlang:refactor-rename', _handleRenameRefactor);
  }

  void dispose() => _commands.dispose();

  void _addCommand(String id, _RefactorHandler handler) {
    _commands.add(atom.commands.add('atom-text-editor', id, (e) {
      TextEditor editor = e.editor;
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

      handler(path, offset, end, text);
    }));
  }

  void _handleExtractLocal(String path, int offset, int end, String text) {
    // Check if extract local can be performed
    _checkRefactoringAvailable(
        Refactorings.EXTRACT_LOCAL_VARIABLE, path, offset, end,
        (AvailableRefactoringsResult result) {
      // TODO: use the rename refactoring feedback
      // to better select the ID being renamed
      // and whether to extract all instances
      String oldName = '';
      bool extractAll = false;

      promptUser('Extract local variable - enter the variable name:',
          defaultText: oldName, selectText: true).then((String newName) {
        // Abort if user cancels the operation or nothing to do
        if (newName == null) return;
        newName = newName.trim();
        if (newName == '' || newName == oldName) return;

        RefactoringOptions options = new ExtractLocalVariableRefactoringOptions(
          name: newName,
          extractAll: extractAll
        );
        _performRefactoring(Refactorings.EXTRACT_LOCAL_VARIABLE, options, path,
            offset, end, "Extracted '${newName}'.");
      });
    });
  }

  void _handleInlineLocal(String path, int offset, int end, String text) {
    String name = _findIdentifier(text, offset);

    // Perform the refactoring
    RefactoringOptions options = null;
    _performRefactoring(Refactorings.INLINE_LOCAL_VARIABLE, options, path, offset, end,
        "Inlined local variable '${name}'.");
  }

  void _handleRenameRefactor(String path, int offset, int end, String text) {
    String oldName = _findIdentifier(text, offset);

    // Check if rename can be performed
    _checkRefactoringAvailable(Refactorings.RENAME, path, offset, end,
        (AvailableRefactoringsResult result) {
      // TODO: use the rename refactoring feedback
      // to better select the ID being renamed.

      promptUser('Rename refactor - enter the new name:',
          defaultText: oldName, selectText: true).then((String newName) {
        // Abort if user cancels the operation or nothing to do
        if (newName == null) return;
        newName = newName.trim();
        if (newName == '' || newName == oldName) return;

        // Perform the refactoring
        RefactoringOptions options = new RenameRefactoringOptions(newName: newName);
        _performRefactoring(Refactorings.RENAME, options, path, offset, end,
            "Renamed '${oldName}' to '${newName}'.");
      });
    });
  }

  /// If [refactoringName] can be triggered at the given location,
  /// then call [refactor].
  void _checkRefactoringAvailable(String refactoringName, String path,
      int offset, int end, refactor(AvailableRefactoringsResult result)) {
    Job job = new AnalysisRequestJob(_jobName(refactoringName), () {
      return analysisServer
          .getAvailableRefactorings(path, offset, end - offset)
          .then((AvailableRefactoringsResult result) {
        if (result == null) {
          atom.beep();
          return;
        }

        // Check if the desired refactoring is available
        List refactorings = result.kinds;
        bool canRefactor = refactorings.contains(refactoringName);
        if (!canRefactor) {
          atom.beep();
          return;
        }

        // Continue with the refactoring
        refactor(result);
      });
    });

    // TODO: Timeout if the refactor request takes too long?
    job.schedule();
  }

  /// Request [refactoringName] changes from the server and apply them.
  _performRefactoring(String refactoringName, RefactoringOptions options,
      String path, int offset, int end, String successMsg) {
    Job job = new AnalysisRequestJob(_jobName(refactoringName), () {
      return analysisServer.getRefactoring(
        refactoringName,
        path, offset,
        end - offset,
        false,
        options: options
      ).then((RefactoringResult result) {
        // Abort if refactoring failed.
        if (result == null) return;

        // Apply refactoring.
        _applyRefactoringResult(refactoringName, result, successMsg, path);
      });
    });
    job.schedule();
  }

  /// Apply the refactoring result specified by the server.
  void _applyRefactoringResult(String refactoringName, RefactoringResult result,
      String successMsg, String path) {
    // TODO: use optionsProblems
    // TODO: use finalProblems
    // TODO: use feedback
    if (result.initialProblems.isNotEmpty) {
      atom.notifications.addError('Unable to ${_readableName(refactoringName)}',
          detail: '${result.initialProblems.first.message}');
      atom.beep();
      return;
    }

    SourceChange change = result.change;
    if (change == null) {
      atom.notifications.addError(
        'Unable to ${_readableName(refactoringName)}',
        detail: 'No change information returned.'
      );
      atom.beep();
      return;
    }

    // Remove any 'potential' edits. The analysis server sends over things
    // like edits to package: files.
    List<SourceFileEdit> sourceFileEdits = change.edits;
    sourceFileEdits.forEach((SourceFileEdit fileEdit) {
      fileEdit.edits.removeWhere((SourceEdit edit) => edit.id != null);
    });
    sourceFileEdits.removeWhere((SourceFileEdit fileEdit) => fileEdit.edits.isEmpty);

    var apply = () {
      _applyEdits(sourceFileEdits, successMsg).then((_) {
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

    notification = atom.notifications.addInfo(
      'Refactor ${sourceFileEdits.length} files?',
      detail: fileSummary,
      dismissable: true,
      buttons: [
        new NotificationButton('Continue', userConfirmed),
        new NotificationButton('Cancel', userCancelled)
      ]
    );
  }

  /// Apply the source edits, displaying [successMsg] once complete.
  Future _applyEdits(List<SourceFileEdit> sourceFileEdits, String successMsg) {
    return Future.forEach(sourceFileEdits, (SourceFileEdit edit) {
      return atom.workspace.open(
        edit.file,
        options: {'searchAllPanes': true}
      ).then((TextEditor editor) {
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

  /// Translate refactoring id to job name
  String _jobName(String id) => id.toLowerCase().replaceAll('_', ' ');

  /// Translate refactoring id to human readable name
  String _readableName(String id) => id.toLowerCase().replaceAll('_', ' ');
}
