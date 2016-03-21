import 'package:atom/utils/disposable.dart';

import '../analysis_server.dart';
import '../atom.dart';
import '../atom_utils.dart';
import '../state.dart';
import 'analysis_server_lib.dart' show FindTopLevelDeclarationsResult;
import 'references.dart';

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
      editor.getElement().focused();

      // Abort if user cancels the operation or nothing to do.
      if (searchTerm == null) return;
      searchTerm = searchTerm.trim();
      if (searchTerm.isEmpty) return;

      _lastSearchTerm = searchTerm;

      new AnalysisRequestJob('Find type', () {
        return analysisServer.server.search.findTopLevelDeclarations(searchTerm).then(
            (FindTopLevelDeclarationsResult result) {
          if (result == null || result.id == null) {
            atom.beep();
            return;
          } else {
            FindReferencesView.showView(new ReferencesSearch(result.id, 'Find Type', searchTerm));
          }
        });
      }).schedule();
    });
  }

  void dispose() => disposables.dispose();
}
