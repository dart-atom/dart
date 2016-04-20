
/// A view and status line decoration for visualizing errors.
library atom.errors;

import 'dart:async';
import 'dart:html' show Element;

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';

import '../analysis/analysis_server_lib.dart' hide Element;
import '../analysis/quick_fixes.dart';
import '../atom_statusbar.dart';
import '../elements.dart';
import '../linter.dart';
import '../state.dart';
import '../views.dart';

const String errorViewId = 'errors';

final String _errorPref = '${pluginId}.showErrorsView';

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
      'atom-workspace', '${pluginId}:toggle-errors-view', (_) => toggleView()
    ));

    enabled = atom.config.getValue(_errorPref);
    view = new ErrorsView(enabled);
    statusElement = new ErrorsStatusElement(this, enabled);

    onProcessedErrorsChanged.listen(_handleErrorsChanged);
    _handleErrorsChanged([]);

    disposables.add(atom.workspace.observeActivePaneItem(_focusChanged));

    _sub = atom.config.onDidChange(_errorPref).listen(_togglePrefs);

    // Check to see if this is our first run.
    if (atom.config.getValue(_initKeyPath) != true) {
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

  void toggleView() {
    if (view.isViewActive()) {
      view.showView(false);
    } else if (view.isViewShowing()) {
      viewGroupManager.activateView(view.id);
    } else {
      view.showView(true);
    }
  }

  void _togglePrefs(bool value) {
    enabled = value;

    // Sync the UI.
    if (view.isViewShowing() && !enabled) view.showView(false);
    if (!view.isViewShowing() && enabled) view.showView(true);
    if (statusElement.isShowing() && !enabled) statusElement.hide();
    if (!statusElement.isShowing() && enabled) statusElement.show();

    // Toggle linter settings.
    atom.config.setValue('linter.showErrorPanel', !enabled);
    atom.config.setValue('linter.displayLinterInfo', !enabled);
  }

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
        .where((AnalysisError e) => e.location.file.startsWith(_focusedDir))
        .toList();
    }

    String shortName = _focusedDir == null ? null : fs.basename(_focusedDir);

    statusElement._handleErrorsChanged(filteredErrors);
    view._handleErrorsChanged(filteredErrors, focus: shortName);
  }
}

class ErrorsView extends View {
  CoreElement target;
  CoreElement countElement;
  CoreElement focusElement;

  ErrorsView(bool enabled) {
    root.toggleClass('errors-view', true);
    root.toggleClass('dartlang', true);

    toolbar.add([
      countElement = div(c: 'errors-count'),
      focusElement = div(c: 'badge focus-title')
    ]);

    content.toggleClass('tab-scrollable');
    content.element.tabIndex = 1;

    if (state['errorViewShowing'] == null) {
      state['errorViewShowing'] = enabled;
    }

    showView(state['errorViewShowing'] != false);

    root.listenForUserCopy();
  }

  String get id => errorViewId;

  String get label => 'Errors';

  bool isViewShowing() => viewGroupManager.hasViewId(id);

  bool isViewActive() {
    return isViewShowing() ? viewGroupManager.isActiveId(id) : false;
  }

  void showView(bool show) {
    if (isViewShowing() == show) return;

    state['errorViewShowing'] = show;

    if (show) {
      viewGroupManager.addView('bottom', this);
    } else {
      viewGroupManager.removeViewId(id);
    }
  }

  void dispose() { }

  void _handleErrorsChanged(List<AnalysisError> errors, {String focus}) {
    // Update the main view.
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
      countElement.add(span(c: 'badge badge-info')
          ..text = '${infoCount} ${pluralize('info', infoCount)}');
    }
  }

  Element _cvtError(AnalysisError error) {
    String type = error.severity == 'ERROR'
        ? ' badge-error' : error.severity == 'WARNING'
        ? ' badge-warning' : ' badge-info';
    String location = '${atom.project.relativizePath(error.location.file)[1]}'
        ', line ${error.location.startLine}';

    CoreElement badge;

    CoreElement item = div(c: 'errors-item')..add([
      badge = span(text: error.severity.toLowerCase(),
          c: 'badge badge-flexible${type} error-type')
    ]);

    if (error.hasFix != null && error.hasFix) {
      CoreElement quickfix = item.add(div(c: 'icon-tools quick-fix'));
      quickfix.click(() {
        _jumpTo(error.location).then((TextEditor editor) {
          // Show the quick fix menu.
          QuickFixHelper helper = deps[QuickFixHelper];
          helper.displayQuickFixes(editor);

          // Show a toast with the keybinding (one time).
          if (state['_quickFixBindings'] != true) {
            atom.notifications.addInfo(
              'Show quick fixes using `ctrl-1` or `alt-enter`.');
            state['_quickFixBindings'] = true;
          }
        });
      });
    }

    CoreElement message;
    CoreElement ahref;

    item.add([
      message = span(text: error.message),
      ahref = new CoreElement('a', text: location, classes: 'text-muted')
    ]);

    badge.click(() => _jumpTo(error.location));
    message.click(() => _jumpTo(error.location));
    ahref.click(() => _jumpTo(error.location));

    return item.element;
  }

  Future<TextEditor> _jumpTo(Location location) {
    Map options = {
      'initialLine': location.startLine,
      'initialColumn': location.startColumn,
      'searchAllPanes': true
    };

    // If we're editing the target file, then use the current editor.
    var ed = atom.workspace.getActiveTextEditor();
    if (ed != null && ed.getPath() == location.file) {
      options['searchAllPanes'] = false;
    }

    return atom.workspace.openPending(location.file, options: options).then(
        (TextEditor editor) {
      // Select offset to length.
      TextBuffer buffer = editor.getBuffer();
      editor.setSelectedBufferRange(new Range.fromPoints(
        buffer.positionForCharacterIndex(location.offset),
        buffer.positionForCharacterIndex(location.offset + location.length)
      ));
      return editor;
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
      _badgeSpan = span(c: 'badge subtle')
    ]);

    _element.click(parent.toggleView);

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
    int infoCount = 0;

    for (int i = 0; i < len; i++) {
      AnalysisError error = errors[i];
      if (error.severity == 'ERROR') errorCount++;
      if (error.severity == 'WARNING') warningCount++;
      if (error.severity == 'INFO') infoCount++;
    }

    bool hasIssues = errorCount != 0 || warningCount != 0;

    if (hasIssues) {
      _badgeSpan.toggleClass('badge-error', errorCount > 0);
      _badgeSpan.toggleClass('badge-warning', errorCount == 0);
      _badgeSpan.toggleClass('subtle', false);

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
      _badgeSpan.text = infoCount == 0
          ? 'no errors' : '${infoCount} ${pluralize('item', infoCount)}';
      _badgeSpan.toggleClass('badge-error', false);
      _badgeSpan.toggleClass('badge-warning', false);
      _badgeSpan.toggleClass('subtle', true);
    }
  }
}
