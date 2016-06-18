library atom.formatting;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/process.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../analysis_server.dart';
import '../editors.dart';
import '../state.dart';

final Logger _logger = new Logger('formatting');

// Get the current preferred line length for Dart files.
int get _prefLineLength =>
    atom.config.getValue('editor.preferredLineLength', scope: ['source.dart']);

class FormattingManager implements Disposable {
  Disposables _commands = new Disposables();

  FormattingManager() {
    _commands.add(atom.commands.add('.tree-view', 'dartlang:dart-format', (e) {
      formatFile(e.targetFilePath);
    }));
    _commands.add(atom.commands.add('atom-text-editor', 'dartlang:dart-format', (e) {
      formatEditor(e.editor);
    }));
  }

  void dispose() => _commands.dispose();

  static void formatFile(String path) {
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
        atom.notifications.addError('Error while formatting', description: result.stderr);
      }
    });
  }

  /// Formats a [TextEditor]. Returns false if the editor was not formatted;
  /// true if it was.
  static Future<bool> formatEditor(TextEditor editor, {bool quiet: false}) {
    String path = editor.getPath();

    if (projectManager.getProjectFor(path) == null) {
      atom.beep();
      return new Future.value(false);
    }

    if (!analysisServer.isActive) {
      atom.beep();
      return new Future.value(false);
    }

    Range range = editor.getSelectedBufferRange();
    TextBuffer buffer = editor.getBuffer();
    int offset = buffer.characterIndexForPosition(range.start);
    int end = buffer.characterIndexForPosition(range.end);

    // TODO: If range.isNotEmpty, just format the given selection?
    return analysisServer
        .format(path, offset, end - offset, lineLength: _prefLineLength)
        .then((FormatResult result) {
      if (result.edits.isEmpty) {
        if (!quiet) atom.notifications.addSuccess('No formatting changes.');
        return false;
      } else {
        if (!quiet) atom.notifications.addSuccess('Formatting successful.');
        applyEdits(editor, result.edits);
        editor.setSelectedBufferRange(new Range.fromPoints(
            buffer.positionForCharacterIndex(result.selectionOffset),
            buffer.positionForCharacterIndex(
                result.selectionOffset + result.selectionLength)));
        return true;
      }
    }).catchError((e) {
      if (e is RequestError) {
        if (!quiet) {
          atom.notifications
              .addError('Error while formatting', description: e.message);
        }
      } else {
        atom.beep();
        _logger.warning('error when formatting: ${e}');
      }
      return false;
    });
  }
}
