
library atom.quick_fixes;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';
import 'package:logging/logging.dart';

import '../analysis_server.dart';
import '../atom_autocomplete.dart';
import '../editors.dart';
import '../state.dart';
import 'analysis_server_lib.dart';

final Logger _logger = new Logger('quick-fixes');

class QuickFixHelper implements Disposable {
  Disposables disposables = new Disposables();

  QuickFixHelper() {
    disposables.add(atom.commands.add('atom-text-editor',
        'dartlang:quick-fix', (event) => _handleQuickFix(event.editor)));
  }

  /// Open the list of available quick fixes for the given editor at the current
  /// location. The editor should be visible and active.
  void displayQuickFixes(TextEditor editor) =>
      _handleQuickFix(editor, autoFix: false);

  void dispose() => disposables.dispose();

  void _handleQuickFix(TextEditor editor, {bool autoFix: true}) {
    String path = editor.getPath();
    Range range = editor.getSelectedBufferRange();
    int offset = editor.getBuffer().characterIndexForPosition(range.start);
    int length = editor.getBuffer().characterIndexForPosition(range.end) - offset;

    Job job = new AnalysisRequestJob('quick fix', () async {
      Future<AssistsResult> assistsFuture = analysisServer.getAssists(path, offset, length);
      FixesResult fixes = await analysisServer.getFixes(path, offset);
      AssistsResult assists = await assistsFuture;

      _handleFixesResult(fixes, assists, editor, autoFix: autoFix);
    });
    job.schedule();
  }

  void _handleFixesResult(FixesResult result, AssistsResult assists,
      TextEditor editor, {bool autoFix: true}) {
    List<AnalysisErrorFixes> fixes = result.fixes;

    if (fixes.isEmpty && assists.assists.isEmpty) {
      atom.beep();
      return;
    }

    List<_Change> changes = new List.from(
        fixes.expand((fix) => fix.fixes.map(
          (SourceChange change) => new _Change(change, fix.error))));

    changes.addAll(
        assists.assists.map((SourceChange change) => new _Change(change)));

    if (autoFix && changes.length == 1 && assists.assists.isEmpty) {
      // Apply the fix.
      _applyChange(editor, changes.first.change);
    } else {
      int i = 0;
      var renderer = (_Change change) {
        // We need to create suggestions with unique text replacements.
        return new Suggestion(
          text: 'fix_${++i}',
          replacementPrefix: '',
          displayText: change.change.message,
          rightLabel: change.isAssist ? 'assist' : 'quick-fix',
          description: change.isAssist ? null : change.error.message,
          type: change.isAssist ? 'attribute' : 'function'
        );
      };

      // Show a selection dialog.
      chooseItemUsingCompletions(editor, changes, renderer).then((_Change choice) {
        editor.undo();
        _applyChange(editor, choice.change);
      });
    }
  }
}

class _Change {
  final SourceChange change;
  final AnalysisError error;

  _Change(this.change, [this.error]);

  bool get isAssist => error == null;

  String toString() {
    return error == null ? change.message : '${error.message}: ${change.message}';
  }
}

void _applyChange(TextEditor currentEditor, SourceChange change) {
  List<SourceFileEdit> sourceFileEdits = change.edits;
  List<LinkedEditGroup> linkedEditGroups = change.linkedEditGroups;

  Future.forEach(sourceFileEdits, (SourceFileEdit edit) {
    return atom.workspace.open(edit.file,
        options: {'searchAllPanes': true}).then((TextEditor editor) {
      applyEdits(editor, edit.edits);
      int index = sourceFileEdits.indexOf(edit);
      if (index >= 0 && index < linkedEditGroups.length) {
        selectEditGroup(editor, linkedEditGroups[index]);
      }
    });
  }).then((_) {
    String fileSummary = sourceFileEdits.map((edit) => edit.file).join('\n');
    if (sourceFileEdits.length == 1) fileSummary = null;
    atom.notifications.addSuccess(
        'Executed quick fix: ${toStartingLowerCase(change.message)}',
        detail: fileSummary);

    // atom.workspace.open(currentEditor.getPath(),
    //     options: {'searchAllPanes': true}).then((TextEditor editor) {
    //   if (change.selection != null) {
    //     editor.setCursorBufferPosition(
    //         editor.getBuffer().positionForCharacterIndex(change.selection.offset));
    //   } else if (linkedEditGroups.isNotEmpty) {
    //     selectEditGroups(currentEditor, linkedEditGroups);
    //   }
    // });
  }).catchError((e) {
    atom.notifications.addError('Error Performing Rename', detail: '${e}');
  });
}
