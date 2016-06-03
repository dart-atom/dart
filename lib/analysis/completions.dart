import 'dart:async';

import 'package:atom/node/config.dart';
import 'package:atom/node/workspace.dart';
import 'package:logging/logging.dart';

import '../atom_autocomplete.dart';
import '../state.dart';
import 'analysis_server_lib.dart' show CompletionResults, CompletionSuggestion,
    SuggestionsResult;

final Logger _logger = new Logger('completions');

const CompletionSuggestionKind_IDENTIFIER = 'IDENTIFIER';

class DartAutocompleteProvider extends AutocompleteProvider {
  static const _suggestionKindMap = const <String, String>{
    CompletionSuggestionKind_IDENTIFIER: 'identifier',
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

  static final Set<String> _elided = new Set.from(['for ()']);

  DartAutocompleteProvider() : super(
      '.source.dart',
      filterSuggestions: true,
      inclusionPriority: 100,
      excludeLowerPriority: true);

  Future<List<Suggestion>> getSuggestions(AutocompleteOptions options) async {
    if (!analysisServer.isActive) return [];

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
    final Set<String> noCompletions = new Set.from(const [';', '{', '}', ']', ')', ',']);

    if (offset > 0) {
      String prevChar = text[offset - 1];
      if (noCompletions.contains(prevChar)) return [];
    }

    if (prefix.length == 1 && noCompletions.contains(prefix)) return [];

    SuggestionsResult result = await analysisServer.server.completion.getSuggestions(path, offset);
    CompletionResults cr = await analysisServer.server.completion.onResults
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
      String p = fileText.substring(replacementOffset, offset);
      if (p != prefix) {
        prefix = p;
        replacementPrefix = prefix;
      }
    }

    // Remove any undesired results.
    List<CompletionSuggestion> results = new List.from(
      cr.results.where((result) => !_elided.contains(result.completion))
    );

    List<Suggestion> suggestions = <Suggestion>[];
    for (CompletionSuggestion cs in results) {
      Suggestion s = _makeSuggestion(cs, prefix, replacementPrefix, replacementOffset);
      if (s != null) suggestions.add(s);
    }
    return suggestions;
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
        if (cs.kind != CompletionSuggestionKind_IDENTIFIER) {
          text += '()';
        }
      } else {

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

        if (cs.kind != CompletionSuggestionKind_IDENTIFIER) {
          text = null;
          snippet = '${cs.completion}($names)\$${++count}';
        }
      }
    }

    // Calculate the selectionOffset.
    int selectionOffset;
    if (cs.selectionOffset != cs.completion.length) {
      selectionOffset = replacementOffset - prefix.length + cs.selectionOffset;
    }

    bool potential = cs.isPotential || cs.importUri != null;

    String iconHTML;

    // Handle material icons in docs.
    if (cs.docSummary != null && cs.docSummary.contains('<i class="material-icons')) {
      String docs = cs.docSummary;
      // <p><i class="material-icons md-36">merge_type</i> &#x2014; material icon named "merge type".</p>
      int startIndex = docs.indexOf('<i class=');
      int endIndex = docs.indexOf('</i>');
      if (endIndex != -1) {
        iconHTML = docs.substring(startIndex, endIndex + 4);
      }
    }

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
      iconHTML: iconHTML,
      description: _describe(cs),
      requiredImport: cs.importUri
    );
  }

  String _sanitizeReturnType(CompletionSuggestion cs) {
    if (cs.element?.kind == 'CONSTRUCTOR') return null;
    return cs.parameterType ?? cs.returnType;
  }

  String _mapType(CompletionSuggestion cs) {
    return _suggestionKindMap[cs.kind] ?? _elementKindMap[cs.element.kind];
  }

  String _describe(CompletionSuggestion cs, {bool useDocs: true}) {
    if (useDocs) {
      if (cs.importUri != null) return "Requires '${cs.importUri}'";

      // Special case a substutition for a character in the material design docs.
      if (cs.docSummary != null) {
        String docs = cs.docSummary;
        if (docs.startsWith('<')) docs = _stripHtml(docs);
        return docs;
      }
    }

    var element = cs.element;
    if (element?.parameters != null) {
      String str = '${element.name}${element.parameters}';

      if (element.kind == 'CONSTRUCTOR') {
        if (element.name.isEmpty) {
          str = '${cs.declaringType}${str}';
        } else {
          str = '${cs.declaringType}.${str}';
        }
      }

      return element.returnType != null ? '${str} → ${element.returnType}' : str;
    }

    return cs.completion;
  }

  /// Returns a human-readable right label for the [kind].
  String _rightLabel(String kind) {
    return _rightLabelMap.putIfAbsent(
        kind, () => kind.toLowerCase().replaceAll('_', ' '));
  }
}

final RegExp _htmlRegex = new RegExp('<[^>]+>');

String _stripHtml(String str) {
  // <p><i class="material-icons md-36">zoom_out_map</i> &#x2014; material icon
  // named "zoom out map".</p>

  str = str.replaceAll('&#x2014;', '-');
  str = str.replaceAll(_htmlRegex, '');

  return str;
}

// String _suggestionToString(CompletionSuggestion cs) {
//   StringBuffer buf = new StringBuffer();
//
//   buf.write('kind: ${cs.kind},');
//   buf.write('relevance: ${cs.relevance},');
//   buf.write('completion: ${cs.completion},');
//   buf.write('selectionOffset: ${cs.selectionOffset},');
//   buf.write('selectionLength: ${cs.selectionLength},');
//   buf.write('isDeprecated: ${cs.isDeprecated},');
//   buf.write('isPotential: ${cs.isPotential},');
//
//   // if (cs.docSummary != null) buf.write('docSummary: ${cs.docSummary},');
//   // if (cs.docComplete != null) buf.write('docComplete: ${cs.docComplete},');
//   if (cs.declaringType != null) buf.write('declaringType: ${cs.declaringType},');
//   if (cs.element != null) buf.write('element: ${cs.element},');
//   if (cs.returnType != null) buf.write('returnType: ${cs.returnType},');
//   if (cs.parameterNames != null) buf.write('parameterNames: ${cs.parameterNames},');
//   if (cs.parameterTypes != null) buf.write('parameterTypes: ${cs.parameterTypes},');
//
//   if (cs.requiredParameterCount != null) buf.write('requiredParameterCount: ${cs.requiredParameterCount},');
//   if (cs.hasNamedParameters != null) buf.write('hasNamedParameters: ${cs.hasNamedParameters},');
//   if (cs.parameterName != null) buf.write('parameterName: ${cs.parameterName},');
//   if (cs.parameterType != null) buf.write('parameterType: ${cs.parameterType},');
//   if (cs.importUri != null) buf.write('importUri: ${cs.importUri},');
//
//   return buf.toString();
// }
