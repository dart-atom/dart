import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../state.dart';
import '../usage.dart' show trackCommand;

final Logger _logger = new Logger('atom.navigation');

// TODO: Finish this class.

class NavigationManager implements Disposable {
  Disposables _commands = new Disposables();

  StreamController<NavigationPosition> _navController =
    new StreamController.broadcast();
  List<NavigationPosition> _history = [];
  List<NavigationPosition> _future = [];

  NavigationManager() {
    _commands.add(atom.commands.add('atom-text-editor',
      'dartlang:return-from-declaration', _handleNavigateReturn));
    _commands.add(atom.commands.add('atom-text-editor[data-grammar~="dart"]',
      'symbols-view:return-from-declaration', _handleNavigateReturn));
  }

  // TODO:
  Stream get onNavigate => _navController.stream;

  Future<TextEditor> jumpToLocation(
    String path, [int line, int column, int length]
  ) {
    _pushCurrentLocation();
    return editorManager.jumpToLocation(path, line, column, length);
  }

  void goBack() {
    if (_history.isNotEmpty) {
      // TODO:

    }
  }

  void goForward() {
    if (_future.isNotEmpty) {

    }
  }

  bool canGoBack() => _history.isNotEmpty;

  bool canGoForward() => _future.isNotEmpty;

  void _handleNavigateReturn(AtomEvent _) {
    // TODO: rework this

    trackCommand('return-from-declaration');

    if (_history.isEmpty) {
      _beep();
      _logger.info('No navigation positions on the stack.');
    } else {
      NavigationPosition pos = _history.removeLast();
      editorManager.jumpToLocation(pos.path, pos.line, pos.column, pos.length);
    }
  }

  void _pushCurrentLocation() {
    TextEditor editor = atom.workspace.getActiveTextEditor();

    if (editor != null) {
      Range range = editor.getSelectedBufferRange();
      if (range == null) return;

      int length = range.isSingleLine() ? range.end.column - range.start.column : null;
      if (length == 0) length = null;

      Point start = range.start;
      _history.add(
          new NavigationPosition(editor.getPath(), start.row, start.column, length));
    }
  }

  void _beep() => atom.beep();

  void dispose() => _commands.dispose();
}

class NavigationPosition {
  final String path;
  final int line;
  final int column;
  final int length;

  NavigationPosition(this.path, this.line, this.column, [this.length]);

  String toString() => '[${path} ${line}:${column}]';
}
