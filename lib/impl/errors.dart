
/// A view and status line decoration for visualizing errors.
library atom.errors;

import 'dart:async';
import 'dart:html' show Element;

import '../analysis/analysis_server_lib.dart' hide Element;
import '../atom.dart';
import '../atom_statusbar.dart';
import '../atom_utils.dart';
import '../elements.dart';
import '../linter.dart';
import '../state.dart';
import '../utils.dart';
import '../views.dart';

final String _errorPref = '${pluginId}.useErrorsView';
final String _initKeyPath = '_dartlang._errorsInitialized';

class ErrorsController implements Disposable {
  Disposables disposables = new Disposables();
  StreamSubscription _sub;

  ErrorsView view;
  ErrorsStatusElement statusElement;

  String _focusedDir;
  List<AnalysisError> _cachedErrors = [];

  bool enabled = false;

  ErrorsController() {
    disposables.add(atom.commands.add(
      'atom-workspace', '${pluginId}:toggle-errors-view', (_) => _toggleView()
    ));

    enabled = atom.config.getValue(_errorPref);

    view = new ErrorsView(enabled);
    statusElement = new ErrorsStatusElement(this, enabled);

    onProcessedErrorsChanged.listen(_handleErrorsChanged);
    _handleErrorsChanged([]);

    disposables.add(atom.workspace.observeActivePaneItem(_focusChanged));

    _sub = atom.config.onDidChange(_errorPref).listen(_togglePrefs);

    // Check to see if this is our first run.
    bool firstRun = atom.config.getValue(_initKeyPath) != true;
    if (firstRun) {
      atom.config.setValue(_initKeyPath, true);
      _togglePrefs(true);
    }
  }

  void dispose() {
    _sub.cancel();
    disposables.dispose();
    statusElement.dispose();
    view.dispose();
  }

  void _togglePrefs(bool value) {
    enabled = value;

    // Sync the UI.
    if (view.isVisible() && !enabled) _toggleView();
    if (!view.isVisible() && enabled) _toggleView();
    if (statusElement.isShowing() && !enabled) statusElement.hide();
    if (!statusElement.isShowing() && enabled) statusElement.show();

    // Toggle linter settings.
    atom.config.setValue('linter.showErrorPanel', !enabled);
    atom.config.setValue('linter.showErrorTabFile', !enabled);
    atom.config.setValue('linter.showErrorTabProject', !enabled);
  }

  void _toggleView() => view.toggle();

  void initStatusBar(StatusBar statusBar) {
    statusElement._init(statusBar);
  }

  void _focusChanged(_) {
    TextEditor editor = atom.workspace.getActiveTextEditor();
    if (editor == null) return;
    String path = editor.getPath();
    if (path == null) return;

    final String newFocus = atom.project.relativizePath(path)[0];

    if (newFocus != _focusedDir) {
      _focusedDir = newFocus;
      _handleErrorsChanged(_cachedErrors);
    }
  }

  void _handleErrorsChanged(List<AnalysisError> errors) {
    _cachedErrors = errors;

    List<AnalysisError> filteredErrors = errors;

    if (_focusedDir != null) {
      filteredErrors = filteredErrors
        .where((AnalysisError error) => error.location.file.startsWith(_focusedDir))
        .toList();
    }

    String shortName = _focusedDir == null ? null : basename(_focusedDir);

    statusElement._handleErrorsChanged(filteredErrors);
    view._handleErrorsChanged(filteredErrors, focus: shortName);
  }
}

class ErrorsView extends AtomView {
  CoreElement target;
  CoreElement body;
  CoreElement countElement;
  CoreElement focusElement;

  ErrorsView(bool enabled) : super('Errors', classes: 'errors-view dartlang', prefName: 'Errors',
      rightPanel: false, cancelCloses: false, showTitle: false) {
    //root.toggleClass('tree-view', false);

    content.add([
      body = div(),
      div(c: 'text-muted errors-focus-area')..add([
        countElement = div(c: 'errors-count'),
        focusElement = div(c: 'badge focus-title')
      ])
    ]);

    state['errorViewShowing'] = enabled;

    bool hidden = state['errorViewShowing'] == false;
    hidden ? hide() : show();
  }

  void show() {
    super.show();
    state['errorViewShowing'] = true;
  }

  void hide() {
    super.hide();
    state['errorViewShowing'] = false;
  }

  void _handleErrorsChanged(List<AnalysisError> errors, {String focus}) {
    // Update the main view.
    body.element.children.clear();

    if (errors.isEmpty) {
      body.add(
        div(c: 'errors-item')..add(
          span(text: 'No issues.', c: 'text-muted')
        )
      );
    } else {
      body.element.children.addAll(errors.map(_cvtError));
    }

    // Update the focus label.
    if (focus != null) {
      focusElement.text = focus;
      focusElement.element.style.display = 'inline-block';
    } else {
      focusElement.element.style.display = 'none';
    }

    // Update the issues count.
    int len = errors.length;
    int errorCount = 0;
    int warningCount = 0;
    int infoCount = 0;

    for (int i = 0; i < len; i++) {
      AnalysisError error = errors[i];
      if (error.severity == 'ERROR') errorCount++;
      else if (error.severity == 'WARNING') warningCount++;
      else infoCount++;
    }

    countElement.element.children.clear();
    if (errorCount > 0) {
      countElement.add(span(c: 'badge badge-error')
          ..text = '${errorCount} ${pluralize('error', errorCount)}');
    }
    if (warningCount > 0) {
      countElement.add(span(c: 'badge badge-warning')
          ..text = '${warningCount} ${pluralize('warning', warningCount)}');
    }
    if (infoCount > 0) {
      countElement.add(span(c: 'badge')
          ..text = '${infoCount} ${pluralize('info', infoCount)}');
    }
  }

  Element _cvtError(AnalysisError error) {
    String type = error.severity == 'ERROR'
        ? ' badge-error' : error.severity == 'WARNING' ? ' badge-warning' : '';
    String locationText = '${atom.project.relativizePath(error.location.file)[1]}'
        ', line ${error.location.startLine}';

    CoreElement item = div(c: 'errors-item')..add([
      span(text: error.severity.toLowerCase(), c: 'badge badge-flexible${type}'),
      span(text: error.message),
      new CoreElement('a', text: locationText, classes: 'text-muted'),
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

  bool _showing;

  Tile statusTile;

  CoreElement _element;
  CoreElement _badgeSpan;

  ErrorsStatusElement(this.parent, this._showing);

  bool isShowing() => _showing;

  void show() {
    _element.element.style.display = 'inline-block';
    _showing = true;
  }

  void hide() {
    _element.element.style.display = 'none';
    _showing = false;
  }

  void dispose() {
    if (statusTile != null) statusTile.destroy();
  }

  void _init(StatusBar statusBar) {
    _element = div(c: 'dartlang')..inlineBlock()..add([
      _badgeSpan = span(c: 'badge text-subtle') // badge-small
    ]);

    _element.click(parent._toggleView);

    statusTile = statusBar.addLeftTile(item: _element.element, priority: -100);

    if (!isShowing()) {
      _element.element.style.display = 'none';
    }

    _handleErrorsChanged([]);
  }

  void _handleErrorsChanged(List<AnalysisError> errors) {
    if (_element == null) return;

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
      //_badgeSpan.element.style.display = 'inline';
      _badgeSpan.toggleClass('badge-error', errorCount > 0);
      _badgeSpan.toggleClass('badge-warning', errorCount == 0);
      _badgeSpan.toggleClass('text-subtle', false);
      //_badgeSpan.text = (errorCount + warningCount).toString();

      // 4 errors, 1 warning
      if (errorCount > 0 && warningCount > 0) {
        int total = errorCount + warningCount;
        _badgeSpan.text = '${total} ${pluralize('issue', total)}';
      } else if (errorCount > 0) {
        _badgeSpan.text = '${errorCount} ${pluralize('error', errorCount)}';
      } else {
        _badgeSpan.text = '${warningCount} ${pluralize('warning', warningCount)}';
      }
    } else {
      _badgeSpan.text = 'no errors';
      _badgeSpan.toggleClass('badge-error', false);
      _badgeSpan.toggleClass('badge-warning', false);
      _badgeSpan.toggleClass('text-subtle', true);
    }
  }
}
