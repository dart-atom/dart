
library atom.references;

import 'package:logging/logging.dart';

import '../atom.dart';
import '../elements.dart';
import '../state.dart';
import '../utils.dart';
import 'analysis_server_gen.dart';

final Logger _logger = new Logger('references');

class FindReferencesHelper implements Disposable {
  Disposable _command;
  FindReferencesView _view;

  FindReferencesHelper() {
    _command = atom.commands.add(
        'atom-text-editor', 'dartlang:find-references', _handleReferences);
  }

  void dispose() {
    _command.dispose();
    if (_view != null) _view.dispose();
  }

  void _handleReferences(AtomEvent event) => _handleReferencesEditor(event.editor);

  void _handleReferencesEditor(TextEditor editor) {
    if (analysisServer.isActive) {
      String path = editor.getPath();
      Range range = editor.getSelectedBufferRange();
      int offset = editor.getBuffer().characterIndexForPosition(range.start);

      analysisServer.findElementReferences(path, offset, false).then(
          (FindElementReferencesResult result) {
        if (result.id == null) {
          _beep();
        } else {
          // TODO: Flash the token that we're finding references to?
          if (_view == null) _view = new FindReferencesView();
          _view._showView(result);
        }
      }).catchError((_) => _beep());
    } else {
      _beep();
    }
  }

  void _beep() => atom.beep();
}

class FindReferencesView extends AtomView {
  //FindElementReferencesResult _currentResult;

  FindReferencesView() : super('References', prefName: 'References');

  void _showView(FindElementReferencesResult result) {
    //_currentResult = result;

    // TODO:
    atom.notifications.addInfo('Under construction');

    show();
  }

  void hide() {
    // TODO: cancel any active search

    super.hide();
  }
}
