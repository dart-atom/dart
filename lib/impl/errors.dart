
/// A view and status line decoration for visualizing errors.
library atom.errors;

import 'dart:html' show Element;

import 'package:atom_dartlang/analysis/analysis_server_gen.dart' hide Element;

import '../atom.dart';
import '../atom_statusbar.dart';
import '../elements.dart';
import '../linter.dart';
import '../state.dart';
import '../utils.dart';

// TODO: preferences

// linter:
//   showErrorPanel: false

// TODO: focus on the current project

class ErrorsController implements Disposable {
  Disposables disposables = new Disposables();

  ErrorsView view;
  ErrorsStatusElement statusElement;

  ErrorsController() {
    disposables.add(atom.commands.add(
      'atom-workspace', '${pluginId}:toggle-errors-view', (_) => _toggleView()
    ));

    _restoreView();
    statusElement = new ErrorsStatusElement(this);

    onProcessedErrorsChanged.listen(_handleErrorsChanged);
    _handleErrorsChanged([]);
  }

  void dispose() {
    disposables.dispose();
    statusElement.dispose();
  }

  void _restoreView() {
    view = new ErrorsView();
  }

  void _toggleView() => view.toggle();

  void initStatusBar(StatusBar statusBar) {
    statusElement._init(statusBar);
  }

  void _handleErrorsChanged(List<AnalysisError> errors) {
    statusElement._handleErrorsChanged(errors);
    view._handleErrorsChanged(errors);
  }
}

class ErrorsView extends AtomView {
  CoreElement target;

  ErrorsView() : super('Errors', classes: 'errors-view', prefName: 'Errors',
      rightPanel: false, cancelCloses: false, showTitle: false) {
    root.toggleClass('tree-view');

    // TODO: class to content

    bool hidden = state['errorViewShowing'] == false;
    if (!hidden) show();
  }

  void toggle() => isVisible() ? hide() : show();

  void show() {
    super.show();
    state['errorViewShowing'] = true;
  }

  void hide() {
    super.hide();
    state['errorViewShowing'] = false;
  }

  void _handleErrorsChanged(List<AnalysisError> errors) {
    content.element.children.clear();

    if (errors.isEmpty) {
      content.add(
        div(c: 'errors-item')..add(
          span(text: 'No issues.', c: 'text-muted')
        )
      );
    } else {
      content.element.children.addAll(errors.map(_cvtError));
    }
  }

  Element _cvtError(AnalysisError error) {
    String type = error.severity == 'ERROR'
        ? ' badge-error' : error.severity == 'WARNING' ? ' badge-warning' : '';
    String locationText = '${atom.project.relativizePath(error.location.file)[1]}'
        ', line ${error.location.startLine}';

    // TODO: use type? correction?
    CoreElement item = div(c: 'errors-item')..add([
      span(text: error.severity.toLowerCase(), c: 'badge badge-flexible${type}'),
      span(text: error.message),
      span(text: locationText, c: 'text-muted'),
    ]);

    item.click(() => _jumpTo(error.location));

    return item.element;
  }

  void _jumpTo(Location location) {
    Map options = {
      'initialLine': location.startLine,
      'initialColumn': location.startColumn,
      'searchAllPanes': true
    };

    // If we're editing the target file, then use the current editor.
    var ed = atom.workspace.getActiveTextEditor();
    if (ed != null && ed.getPath() == location.file) options['searchAllPanes'] = false;

    atom.workspace.open(location.file, options: options).then((TextEditor editor) {
      // Select offset to length.
      TextBuffer buffer = editor.getBuffer();
      editor.setSelectedBufferRange(new Range.fromPoints(
        buffer.positionForCharacterIndex(location.offset),
        buffer.positionForCharacterIndex(location.offset + location.length)
      ));
    });
  }
}

class ErrorsStatusElement implements Disposable {
  final ErrorsController parent;

  Tile statusTile;

  CoreElement _element;
  CoreElement _badgeSpan;
  CoreElement _messageSpan;

  ErrorsStatusElement(this.parent);

  void dispose() {
    if (statusTile != null) statusTile.destroy();
  }

  void _init(StatusBar statusBar) {
    _element = div(c: 'errors-status')..inlineBlock()..add([
      _badgeSpan = span(c: 'badge badge-small badge-error'),
      _messageSpan = new CoreElement('a')
    ]);

    _element.click(parent._toggleView);

    statusTile = statusBar.addLeftTile(item: _element.element, priority: -1);
  }

  void _handleErrorsChanged(List<AnalysisError> errors) {
    int len = errors.length;
    int errorCount = 0;
    int warningCount = 0;

    for (int i = 0; i < len; i++) {
      AnalysisError error = errors[i];
      if (error.severity == 'ERROR') errorCount++;
      if (error.severity == 'WARNING') warningCount++;
    }

    bool hasIssues = errorCount != 0 || warningCount != 0;

    if (hasIssues) {
      _badgeSpan.element.style.display = 'inline';
      _badgeSpan.toggleClass('badge-error', errorCount > 0);
      _badgeSpan.toggleClass('badge-warning', errorCount == 0);
      _badgeSpan.text = (errorCount + warningCount).toString();

      // 4 errors and 1 warning
      if (errorCount > 0 && warningCount > 0) {
        _messageSpan.text = '${errorCount} ${pluralize('error', errorCount)} '
          'and ${warningCount} ${pluralize('warning', warningCount)}';
      } else if (errorCount > 0) {
        _messageSpan.text = pluralize('error', errorCount);
      } else {
        _messageSpan.text = pluralize('warning', warningCount);
      }
      _messageSpan.toggleClass('text-subtle', false);
    } else {
      _badgeSpan.element.style.display = 'none';
      _messageSpan.text = 'no issues';
      _messageSpan.toggleClass('text-subtle', true);
    }
  }
}
