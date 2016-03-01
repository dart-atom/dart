part of atom.autocomplete_impl;

class DartAutocompleteProvider extends AutocompleteProvider {
  static const _suggestionKindMap = const <String, String>{
    'IMPORT': 'import',
    'KEYWORD': 'keyword',
    'PARAMETER': 'property',
    'NAMED_ARGUMENT': 'property'
  };

  static const _elementKindMap = const <String, String>{
    'CLASS': 'class',
    'CLASS_TYPE_ALIAS': 'class',
    'CONSTRUCTOR': 'constant', // 'constructor' causes display issues
    'SETTER': 'function',
    'GETTER': 'function',
    'FUNCTION': 'function',
    'METHOD': 'method',
    'LIBRARY': 'import',
    'LOCAL_VARIABLE': 'variable',
    'FUNCTION_TYPE_ALIAS': 'function',
    'ENUM': 'constant',
    'ENUM_CONSTANT': 'constant',
    'FIELD': 'function',
    'PARAMETER': 'property',
    'TOP_LEVEL_VARIABLE': 'variable'
  };

  static Map<String, String> _rightLabelMap = {
    null: null,
    'FUNCTION_TYPE_ALIAS': 'function type'
  };

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

  Future<List<Suggestion>> getSuggestions(AutocompleteOptions options) async {
    if (!analysisServer.isActive) return [];

    Server server = analysisServer.server;
    TextEditor editor = options.editor;
    int offset = editor.getBuffer().characterIndexForPosition(options.bufferPosition);
    String path = editor.getPath();
    String text = editor.getText();
    String prefix = options.prefix;

    // If in a Dart source comment return an empty result.
    ScopeDescriptor descriptor = editor.scopeDescriptorForBufferPosition(options.bufferPosition);
    List<String> scopes = descriptor?.scopes ?? <String>[];
    if (scopes.any((s) => s.startsWith('comment.line') || s.startsWith('comment.block'))) {
      return [];
    }

    // Atom autocompletes right after a semi-colon, and often the user's return
    // key event is captured as a code complete select - inserting an item
    // (inadvertently) into the editor.
    final Set<String> noCompletions = new Set.from(const [';', '{', '}', ']', ',']);

    if (offset > 0) {
      String prevChar = text[offset - 1];
      if (noCompletions.contains(prevChar)) return [];
    }

    if (prefix.length == 1 && noCompletions.contains(prefix)) return [];

    SuggestionsResult result = await server.completion.getSuggestions(path, offset);
    CompletionResults cr = await server.completion.onResults
          .where((cr) => cr.id == result.id)
          .where((cr) => cr.isLast).first;
    return _handleCompletionResults(text, offset, prefix, cr);
  }

  void onDidInsertSuggestion(TextEditor editor, Point triggerPosition,
      Map suggestion) {
    int selectionOffset = suggestion['selectionOffset'];
    if (selectionOffset != null) {
      Point pt = editor.getBuffer().positionForCharacterIndex(selectionOffset);
      editor.setCursorBufferPosition(pt);
    }
  }

  List<Suggestion> _handleCompletionResults(String fileText, int offset, String prefix,
      CompletionResults cr) {
    String replacementPrefix;
    int replacementOffset = cr.replacementOffset;

    // Calculate the prefix based on the insert location and the offset.
    if (replacementOffset < offset) {
      var p = fileText.substring(replacementOffset, offset);
      if (p != prefix) {
        prefix = p;
        replacementPrefix = prefix;
      }
    }

    // Patch-up the analysis server's completion scoring.
    List<CompletionSuggestion> results = new List.from(cr.results
        .where((result) => result.relevance > 500)
        .where((result) => !_elided.contains(result.completion))
        .map(_adjustRelevance));

    results.sort(_compareSuggestions);

    var suggestions = <Suggestion>[];
    for (var cs in results) {
      Suggestion s =
          _makeSuggestion(cs, prefix, replacementPrefix, replacementOffset);
      if (s != null) suggestions.add(s);
    }
    return suggestions;
  }

  /// Returns a [CompletionSuggestion] with an adjusted score.
  CompletionSuggestion _adjustRelevance(CompletionSuggestion suggestion) {
    if (suggestion.kind == 'KEYWORD') {
      return _copySuggestion(suggestion, suggestion.relevance - 1);
    }

    if (suggestion.element?.kind == 'NAMED_ARGUMENT') {
      return _copySuggestion(suggestion, suggestion.relevance + 1);
    }

    return suggestion;
  }

  /// Returns an Atom [Suggestion] from the analyzer's [cs] or null if [cs] is
  /// not a suitable completion given the [prefix] and [replacementOffset].
  Suggestion _makeSuggestion(CompletionSuggestion cs, String prefix, String replacementPrefix,
      int replacementOffset) {
    String text = cs.completion;
    String snippet;
    String displayText;

    // We have something that might take params.
    if (cs.parameterNames != null) {
      // If it takes no parameters, then just append `()`.
      if (cs.parameterNames.isEmpty) {
        text += '()';
      } else {
        text = null;

        // If it has required params, then use a snippet: func(${1:arg}).
        int count = 0;
        String names = cs.parameterNames
            .take(cs.requiredParameterCount)
            .map((name) => '\${${++count}:${name}}')
            .join(', ');

        bool hasOptionalParameters = cs.requiredParameterCount != cs.parameterNames.length;
        if (hasOptionalParameters) {
          // Create a display string with the optional params.
          displayText = _describe(cs, useDocs: false);
        }

        snippet = '${cs.completion}($names)\$${++count}';
      }
    }

    // Filter out completions where suggestion.toLowerCase != prefix.toLowerCase
    String completionPrefix = prefix.toLowerCase();
    if (completionPrefix.isNotEmpty && idRegex.hasMatch(completionPrefix[0])) {
      /// Returns true if the suggestion [s] is incompatible with the prefix [p]
      bool isIncompatible(String s, String pre) =>
          s != null && !s.toLowerCase().startsWith(pre);

      if (isIncompatible(text ?? snippet, completionPrefix)) return null;
    }

    // Calculate the selectionOffset.
    int selectionOffset;
    if (cs.selectionOffset != cs.completion.length) {
      selectionOffset = replacementOffset - completionPrefix.length + cs.selectionOffset;
    }

    bool potential = cs.isPotential || cs.importUri != null;

    return new Suggestion(
        text: text,
        snippet: snippet,
        displayText: displayText,
        replacementPrefix: replacementPrefix,
        selectionOffset: selectionOffset,
        type: _mapType(cs),
        leftLabel: _sanitizeReturnType(cs),
        rightLabel: _rightLabel(cs.element?.kind ?? cs.kind),
        className: cs.isDeprecated
            ? 'suggestion-deprecated'
            : potential ? 'suggestion-potential' : null,
        description: _describe(cs),
        requiredImport: cs.importUri);
  }

  String _sanitizeReturnType(CompletionSuggestion cs) {
    if (cs.element?.kind == 'CONSTRUCTOR') return null;
    return cs.parameterType ?? cs.returnType;
  }

  String _mapType(CompletionSuggestion cs) {
    return _suggestionKindMap[cs.kind] ?? _elementKindMap[cs.element.kind];
  }

  String _describe(CompletionSuggestion cs, {bool useDocs: true}) {
    if (cs.importUri != null) return "Requires '${cs.importUri}'";
    if (useDocs && cs.docSummary != null) return cs.docSummary;

    var element = cs.element;
    if (element?.parameters != null) {
      String str = '${element.name}${element.parameters}';
      return element.returnType != null
          ? '${str} → ${element.returnType}'
          : str;
    }

    return cs.completion;
  }

  /// Returns a human-readable right label for the [kind].
  String _rightLabel(String kind) {
    return _rightLabelMap.putIfAbsent(
        kind, () => kind.toLowerCase().replaceAll('_', ' '));
  }
}

CompletionSuggestion _copySuggestion(CompletionSuggestion s, int relevance) =>
  new CompletionSuggestion(
    s.kind,
    relevance,
    s.completion,
    s.selectionOffset,
    s.selectionLength,
    s.isDeprecated,
    s.isPotential,
    docSummary: s.docSummary,
    docComplete: s.docComplete,
    declaringType: s.declaringType,
    element: s.element,
    returnType: s.returnType,
    parameterNames: s.parameterNames,
    parameterTypes: s.parameterTypes,
    requiredParameterCount: s.requiredParameterCount,
    hasNamedParameters: s.hasNamedParameters,
    parameterName: s.parameterName,
    parameterType: s.parameterType,
    importUri: s.importUri);
