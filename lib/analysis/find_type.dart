import 'package:atom/utils/disposable.dart';

import 'package:logging/logging.dart';

import '../analysis_server.dart';
import '../atom.dart';
import '../atom_utils.dart';
import '../state.dart';
import 'analysis_server_lib.dart' show FindTopLevelDeclarationsResult;
import 'references.dart';

final Logger _logger = new Logger('find_type');

class FindTypeHelper implements Disposable {
  Disposables disposables = new Disposables();

  String _lastSearchTerm;

  FindTypeHelper() {
    disposables.add(atom.commands.add(
      'atom-text-editor', 'dartlang:find-type', (event) => _handleFindType(event.editor)
    ));
  }

  void _handleFindType(TextEditor editor) {
    promptUser('Find type:', defaultText: _lastSearchTerm, selectText: true).then((String searchTerm) {
      // Focus the current editor.
      try {
        editor?.getElement()?.focused();
      } catch (e) {
        _logger.warning('Error focusing editor in _handleFindType', e);
      }

      // Abort if user cancels the operation or nothing to do.
      if (searchTerm == null) return;
      searchTerm = searchTerm.trim();
      if (searchTerm.isEmpty) return;

      _lastSearchTerm = searchTerm;

      new AnalysisRequestJob('Find type', () {
        String term = createInseneitiveRegex(searchTerm);
        return analysisServer.server.search.findTopLevelDeclarations(term).then(
            (FindTopLevelDeclarationsResult result) {
          if (result?.id == null) {
            atom.beep();
            return;
          } else {
            FindReferencesView.showView(new ReferencesSearch(result.id, 'Find Type', searchTerm));
          }
        });
      }).schedule();
    });
  }

  String createInseneitiveRegex(String searchTerm) {
    StringBuffer buf = new StringBuffer();

    for (int i = 0; i < searchTerm.length; i++) {
      String s = searchTerm[i];
      buf.write('[${s.toLowerCase()}${s.toUpperCase()}]');
    }

    return buf.toString();
  }

  void dispose() => disposables.dispose();
}
