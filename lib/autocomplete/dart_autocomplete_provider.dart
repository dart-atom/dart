part of autocomplete;

// TODO: The code completion popup can be very sticky - perhaps due to the
// latency involved in using the analysis server?

class DartAutocompleteProvider extends AutocompleteProvider {
  static final _suggestionKindMap = {
    'IMPORT': 'import',
    'KEYWORD': 'keyword',
    'PARAMETER': 'variable'
  };

  static final _elementKindMap = {
    'CLASS': 'class',
    'CLASS_TYPE_ALIAS': 'class',
    'CONSTRUCTOR': 'constant', // 'constructor' causes display issues
    'SETTER': 'property',
    'GETTER': 'property',
    'FUNCTION': 'function',
    'METHOD': 'method',
    'LOCAL_VARIABLE': 'variable',
    'FUNCTION_TYPE_ALIAS': 'function',
    'ENUM': 'constant',
    'ENUM_CONSTANT': 'constant',
    'FIELD': 'property',
    'PARAMETER': 'variable',
    'TOP_LEVEL_VARIABLE': 'variable'
  };

  static Map _rightLabelMap = {null: null, 'FUNCTION_TYPE_ALIAS': 'function type'};

  static int _compareSuggestions(CompletionSuggestion a, CompletionSuggestion b) {
    if (a.relevance != b.relevance) return b.relevance - a.relevance;
    return a.completion.toLowerCase().compareTo(b.completion.toLowerCase());
  }

  static final Set<String> _elided = new Set.from(['for ()']);

  DartAutocompleteProvider() : super(
      '.source.dart',
      filterSuggestions: true,
      inclusionPriority: 100,
      excludeLowerPriority: true);

  Future<List<Suggestion>> getSuggestions(AutocompleteOptions options) {
    if (!analysisServer.isActive) return new Future.value([]);

    var server = analysisServer.server;
    var editor = options.editor;
    var path = editor.getPath();
    String text = editor.getText();
    int offset = editor.getBuffer().characterIndexForPosition(options.bufferPosition);
    String prefix = options.prefix;

    // If in a Dart source comment return an empty result.
    ScopeDescriptor descriptor = editor.scopeDescriptorForBufferPosition(options.bufferPosition);
    List<String> scopes = descriptor == null ? null : descriptor.scopes;
    if (scopes != null && scopes.any((s) => s.startsWith('comment.line')
        || s.startsWith('comment.block'))) {
      return new Future.value([]);
    }

    // Atom autocompletes right after a semi-colon, and often the user's return
    // key event is captured as a code complete select - inserting an item
    // (inadvertently) into the editor.
    if (prefix == ';') return new Future.value([]);
    if (prefix == '{' || prefix == '}') return new Future.value([]);

    return server.completion.getSuggestions(path, offset).then((result) {
      return server.completion.onResults
          .where((cr) => cr.id == result.id)
          .where((cr) => cr.isLast).first.then((r) {
              return _handleCompletionResults(text, offset, prefix, r);
          });
    });
  }

  void onDidInsertSuggestion(TextEditor editor, Point triggerPosition,
      Map suggestion) {
    String requiredImport = suggestion['requiredImport'];
    if (requiredImport != null) {
      // TODO: Insert it.
      _logger.info('TODO: add an import for ${requiredImport}');
    }

    int selectionOffset = suggestion['selectionOffset'];
    if (selectionOffset != null) {
      Point pt = editor.getBuffer().positionForCharacterIndex(selectionOffset);
      editor.setCursorBufferPosition(pt);
    }
  }

  List<Suggestion> _handleCompletionResults(String fileText, int offset, String prefix,
      CompletionResults cr) {
    List<CompletionSuggestion> results = cr.results;
    String prefixLower = prefix.toLowerCase();
    int replacementOffset = cr.replacementOffset;

    // Calculate the prefix based on the insert location and the offset.
    String _prefix;
    if (replacementOffset < offset) {
      _prefix = fileText.substring(replacementOffset, offset);
      if (_prefix == prefix) _prefix = null;
    }

    results = results
        .where((result) => result.relevance > 500) // filtering from `dart-tools`
        .where((result) => !_elided.contains(result.completion))
        .toList();

    results.sort(_compareSuggestions);

    var suggestions = results.map((CompletionSuggestion cs) {
      String text = cs.completion;
      String snippet = null;

      // We have something that might take params.
      if (cs.parameterNames != null) {
        // If it takes none, then just append `()`.
        if (cs.parameterNames.isEmpty) {
          text += '()';
        } else if (cs.requiredParameterCount != null && cs.requiredParameterCount > 0) {
          // TODO: (dynamic) → dynamic? and () -> dynamic

          // If it has required params, then use a snippet: func(${1:arg}).
          int count = 0;
          String names = cs.parameterNames.take(cs.requiredParameterCount).map(
              (name) => '\${${++count}:${name}}').join(', ');

          //bool hasOptional = cs.requiredParameterCount != cs.parameterNames.length;

          text = null;
          //snippet = '${cs.completion}(${names}, \${${count + 1}:…})\$${count + 2}';
          snippet = '${cs.completion}(${names})\$${++count}';
        } else {
          // Else, leave the cursor within the parans.
          text = null;
          snippet = '${cs.completion}(\$1)\$2';
        }
      }

      // Filter out completions where the suggestions.tolowercase != the prefix.
      String completionPrefix = _prefix != null  ? _prefix.toLowerCase() : prefixLower;
      if (completionPrefix.isNotEmpty && idRegex.hasMatch(completionPrefix[0])) {
        if (text != null && !text.toLowerCase().startsWith(completionPrefix)) {
          return null;
        }
        if (snippet != null && !snippet.toLowerCase().startsWith(completionPrefix)) {
          return null;
        }
      }

      // Calculate the selectionOffset.
      int selectionOffset;
      if (cs.selectionOffset != cs.completion.length) {
        selectionOffset =
            replacementOffset - completionPrefix.length + cs.selectionOffset;
      }

      bool potential = cs.isPotential || cs.importUri != null;

      Suggestion suggestion = new Suggestion(
        type: _mapType(cs),
        leftLabel: _sanitizeReturnType(cs),
        rightLabel: _rightLabel(cs.element != null ? cs.element.kind : cs.kind),
        className:
            cs.isDeprecated ? 'suggestion-deprecated' :
                potential ? 'suggestion-potential' : null,
        description: _describe(cs),
        requiredImport: cs.importUri
      );
      if (text != null) suggestion.text = text;
      if (snippet != null) suggestion.snippet = snippet;
      if (_prefix != null) suggestion.replacementPrefix = _prefix;
      if (selectionOffset != null) suggestion.selectionOffset = selectionOffset;
      return suggestion;
    }).where((suggestion) => suggestion != null).toList();

    return suggestions;
  }

  String _sanitizeReturnType(CompletionSuggestion cs) {
    if (cs.element != null && cs.element.kind == 'CONSTRUCTOR') return null;
    if (cs.parameterType != null) return cs.parameterType;
    return cs.returnType;
  }

  String _mapType(CompletionSuggestion cs) {
    if (_suggestionKindMap[cs.kind] != null) return _suggestionKindMap[cs.kind];
    if (cs.element == null) return null;
    var elementKind = cs.element.kind;
    if (_elementKindMap[elementKind] != null) return _elementKindMap[elementKind];
    return null;
  }

  String _describe(CompletionSuggestion cs) {
    if (cs.importUri != null) return "Requires '${cs.importUri}'";

    var element = cs.element;
    if (element != null && element.parameters != null) {
      String str = '${element.name}${element.parameters}';
      return element.returnType != null ? '${str} → ${element.returnType}' : str;
    }

    // TODO: But, docSummary is always null...
    // See https://github.com/dart-lang/sdk/issues/23694.
    if (cs.docSummary != null) return cs.docSummary;

    return cs.completion;
  }

  String _rightLabel(String str) {
    if (_rightLabelMap[str] != null) return _rightLabelMap[str];
    _rightLabelMap[str] = str.toLowerCase().replaceAll('_', ' ');
    return _rightLabelMap[str];
  }
}
