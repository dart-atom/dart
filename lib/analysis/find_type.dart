import 'package:atom/atom.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../analysis_server.dart';
import '../state.dart';
import 'analysis_server_lib.dart' show FindTopLevelDeclarationsResult, SearchResult, Location;
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
    promptUser(
      'Find type:',
      defaultText: _lastSearchTerm,
      selectText: true,
      isDart: true
    ).then((String searchTerm) {
      try {
        // Focus the current editor.
        editor?.getElement()?.focused();
      } catch (e) {
        _logger.info('Error focusing editor in _handleFindType', e);
      }

      // Abort if user cancels the operation or there's nothing to do.
      if (searchTerm == null) return;

      searchTerm = searchTerm.trim();
      if (searchTerm.isEmpty) {
        atom.beep();
        return;
      }

      _lastSearchTerm = searchTerm;

      AnalysisRequestJob job = new AnalysisRequestJob('Find type', () async {
        String term = _createInsensitiveRegex(searchTerm);
        FindTopLevelDeclarationsResult result =
          await analysisServer.server.search.findTopLevelDeclarations(term);

        if (result?.id == null) {
          atom.beep();
          return;
        }

        List<SearchResult> results = await analysisServer.getSearchResults(result.id);

        if (results.isEmpty) {
          atom.beep();
          return;
        }

        List<SearchResult> exact = results.where((SearchResult result) {
          return result.path.first.name.toLowerCase() == searchTerm.toLowerCase();
        });

        if (exact.length == 1) {
          Location location = exact.first.location;
          navigationManager.jumpToLocation(location.file,
              location.startLine - 1, location.startColumn - 1, location.length);
        } else {
          FindReferencesView.showView(new ReferencesSearch('Find Type', searchTerm, results: results));
        }
      });
      job.schedule();
    });
  }

  String _createInsensitiveRegex(String searchTerm) {
    StringBuffer buf = new StringBuffer();

    for (int i = 0; i < searchTerm.length; i++) {
      String s = searchTerm[i];
      buf.write('[${s.toLowerCase()}${s.toUpperCase()}]');
    }

    return buf.toString();
  }

  void dispose() => disposables.dispose();
}
