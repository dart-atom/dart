
/// A view and status line decoration for visualizing errors.
library atom.errors;

import '../atom.dart';
import '../elements.dart';
import '../state.dart';
import '../utils.dart';

// TODO: preferences

// linter:
//   showErrorPanel: false

// TODO: status line contribution

// TODO: focus on the current project

// TODO: errors view

// TODO: click on the status line toggles the error view

class ErrorsController implements Disposable {
  Disposables disposables = new Disposables();
  ErrorsView view;
  bool viewHidden;

  ErrorsController() {
    disposables.add(atom.commands.add(
      'atom-workspace', '${pluginId}:toggle-errors-view', (_) => _toggleView()
    ));

    _restoreView();
  }

  void dispose() {
    disposables.dispose();
  }

  void _restoreView() {
    view = new ErrorsView();
  }

  void _toggleView() => view.toggle();
}

class ErrorsView extends AtomView {
  CoreElement target;

  ErrorsView() : super('Errors', classes: 'errors-view', prefName: 'Errors',
      rightPanel: false, cancelCloses: false, showTitle: false) {
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
}
