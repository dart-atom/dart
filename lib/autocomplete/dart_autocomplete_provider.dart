part of autocomplete;

class DartAutocompleteProvider extends AutocompleteProvider {
  final typeMap = {
    'class_type_alias': 'class',
    'setter': 'property',
    'getter': 'property',
    'local_variable': 'variable',
    'function_type_alias': 'function',
    'enum': 'constant',
    'enum_constant': 'constant'
  };
  // inclusionPriority: 100, excludeLowerPriority: true, filterSuggestions: true
  DartAutocompleteProvider() : super('.source.dart', filterSuggestions: true);

  Future<List<Suggestion>> getSuggestions(AutocompleteOptions options) {
    var server = analysisServer.server;
    var editor = options.editor;
    var path = editor.getPath();
    var offset = editor.getBuffer().characterIndexForPosition(options.bufferPosition);
    return server.completion.getSuggestions(path, offset).then((result) {
      return server.completion.onResults
        .where((cr) => cr.id == result.id)
        .where((cr) => cr.isLast).first.then(_handleCompletionResults);
      });
  }

  List<Suggestion> _handleCompletionResults(CompletionResults cr) {
    var suggestions = cr.results.map((cs) {
      return new Suggestion(text: cs.completion,
        leftLabel: cs.returnType,
        rightLabel: cs.element != null ? cs.element.kind : cs.kind,
        type: _mapType(cs),
        description: cs.docSummary
      );
    }).toList();

    return suggestions;
  }

  String _mapType(cs) {
    var kind = cs.element != null ? cs.element.kind : cs.kind;
    if (kind != null) kind = kind.toLowerCase();
    var mappedType = typeMap[kind];
    if (mappedType == null) mappedType = kind;
    return mappedType;
  }
}
