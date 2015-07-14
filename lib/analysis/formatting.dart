library atom.formatting;

import 'package:logging/logging.dart';

import '../analysis_server.dart';
import '../atom.dart';
import '../editors.dart';
import '../process.dart';
import '../state.dart';
import '../utils.dart';

final Logger _logger = new Logger('formatting');

// Get the current preferred line length for Dart files.
int get _prefLineLength =>
    atom.config.getValue('editor.preferredLineLength', scope: ['source.dart']);

class FormattingHelper implements Disposable {
  Disposables _commands = new Disposables();

  FormattingHelper() {
    _commands.add(atom.commands.add('.tree-view', 'dartlang:dart-format', (e) {
      _formatFile(e.selectedFilePath);
    }));
    _commands.add(atom.commands.add('atom-text-editor', 'dartlang:dart-format',
        (e) {
      _formatEditor(e.editor);
    }));
  }

  void dispose() => _commands.dispose();

  void _formatFile(String path) {
    if (!sdkManager.hasSdk) {
      atom.beep();
      return;
    }

    // dartfmt -l90 -w lib/analysis/formatting.dart
    List<String> args = [];
    args.add('-l${_prefLineLength}');
    args.add('-w');
    args.add(path);
    sdkManager.sdk.execBinSimple('dartfmt', args).then((ProcessResult result) {
      if (result.exit == 0) {
        atom.notifications.addSuccess('Formatting successful.');
      } else {
        atom.notifications.addError('Error while formatting',
            detail: result.stderr);
      }
    });
  }

  // TODO: Also support formatting just a selection?
  void _formatEditor(TextEditor editor) {
    String path = editor.getPath();

    if (projectManager.getProjectFor(path) == null) {
      atom.beep();
      return;
    }

    if (!analysisServer.isActive) {
      atom.beep();
      return;
    }

    Range range = editor.getSelectedBufferRange();
    TextBuffer buffer = editor.getBuffer();
    int offset = buffer.characterIndexForPosition(range.start);
    int end = buffer.characterIndexForPosition(range.end);

    analysisServer
        .format(path, offset, end - offset, lineLength: _prefLineLength)
        .then((FormatResult result) {
      if (result.edits.isEmpty) {
        atom.notifications.addSuccess('No formatting changes.');
      } else {
        atom.notifications.addSuccess('Formatting successful.');
        applyEdits(editor, result.edits);
        editor.setSelectedBufferRange(new Range.fromPoints(
            buffer.positionForCharacterIndex(result.selectionOffset), buffer
                .positionForCharacterIndex(
                    result.selectionOffset + result.selectionLength)));
      }
    }).catchError((e) {
      if (e is RequestError) {
        atom.notifications.addError('Error while formatting',
            detail: e.message);
      } else {
        atom.beep();
        _logger.warning('error when formatting: ${e}');
      }
    });
  }
}
