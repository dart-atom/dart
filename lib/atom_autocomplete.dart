// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// See the `autocomplete-plus` API [here](https://github.com/atom/autocomplete-plus)
/// and [here](https://github.com/atom/autocomplete-plus/wiki/Provider-API).
library atom.autocomplete;

import 'dart:async';
import 'dart:js';

import 'package:atom/atom.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/src/js.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

final Logger _logger = new Logger('atom.autocomplete');

_AutoCompleteOverride<dynamic> _override;

void triggerAutocomplete(TextEditor editor) {
  atom.commands.dispatch(
    atom.views.getView(editor),
    'autocomplete-plus:activate',
    options: {'activatedManually': false}
  );
}

/// Display the code completion UI with the given list of items, and return the
/// user's selection.
Future/*<T>*/ chooseItemUsingCompletions/*<T>*/(TextEditor editor,
    List<dynamic> items, Suggestion renderer(/*T*/ item)) {
  _override = new _AutoCompleteOverride/*<T>*/(editor, items, renderer);
  triggerAutocomplete(editor);
  return _override.future;
}

List<_AutoCompleteEditorOverride> _overrides = [];

typedef Future<List<Suggestion>> AutoCompleter(AutocompleteOptions options);

void addOverrideAutocompleteForEditor(TextEditor editor, AutoCompleter autoCompleter) {
  _overrides.removeWhere((override) => override.editor == editor);
  _overrides.add(new _AutoCompleteEditorOverride(editor, autoCompleter));
}

void removeOverrideAutocompleteForEditor(TextEditor editor) {
  _overrides.removeWhere((override) => override.editor == editor);
}

abstract class AutocompleteProvider implements Disposable {
  /// Defines the scope selector(s) (can be comma-separated) for which your
  /// provider should receive suggestion requests.
  final String selector;

  /// (optional): Defines the scope selector(s) (can be comma-separated) for
  /// which your provider should not be used.
  final String disableForSelector;

  /// (optional): A number to indicate its priority to be included in a
  /// suggestions request. The default provider has an inclusion priority of 0.
  /// Higher priority providers can suppress lower priority providers with
  /// [excludeLowerPriority].
  final int inclusionPriority;

  /// (optional): Will not use lower priority providers when this provider is
  /// used.
  final bool excludeLowerPriority;

  /// Tell autocomplete to fuzzy filter the results of getSuggestions().
  final bool filterSuggestions;

  AutocompleteProvider(this.selector, {this.disableForSelector,
      this.inclusionPriority, this.excludeLowerPriority, this.filterSuggestions});

  Future<List<Suggestion>> getSuggestions(AutocompleteOptions options);

  void onDidInsertSuggestion(TextEditor editor, Point triggerPosition,
    Map suggestion) { }

  void dispose() { }

  JsObject toProxy() {
    Map map = {
        'selector': selector,
        'getSuggestions': _getSuggestions,
        'onDidInsertSuggestion': _onDidInsertSuggestion,
        'dispose': dispose
    };
    if (disableForSelector != null) map['disableForSelector'] = disableForSelector;
    if (inclusionPriority != null) map['inclusionPriority'] = inclusionPriority;
    if (excludeLowerPriority != null) map['excludeLowerPriority'] = excludeLowerPriority;
    if (filterSuggestions != null) map['filterSuggestions'] = filterSuggestions;
    return jsify(map);
  }

  JsObject _getSuggestions(options) {
    Future<List<JsObject>> f;
    AutocompleteOptions opts = new AutocompleteOptions(options);

    if (_override != null) {
      if (_override.hasShown) {
        _override = null;
      } else if (_override.editor != opts.editor) {
        _logger.info('completions override editor != current editor');
        _override = null;
      }
    }

    /// Returns a [JsObject] representing [s].
    JsObject suggestionToProxy(Suggestion s) => s._toProxy();

    if (_override != null) {
      _override.hasShown = true;
      List<Suggestion> suggestions = _override.renderSuggestions();
      f = new Future.value(suggestions.map(suggestionToProxy).toList());
    } else if (_overrides.any((override) => override.editor == opts.editor)) {
      _AutoCompleteEditorOverride override = _overrides.firstWhere(
        (override) => override.editor == opts.editor);
      Stopwatch timer = new Stopwatch()..start();
      f = override.autoCompleter(opts).then((List<Suggestion> suggestions) {
        _logger.finer(
          'override completion in ${timer.elapsedMilliseconds}ms, '
          '${suggestions.length} results'
        );
        return suggestions.map(suggestionToProxy).toList();
      });
    } else {
      Stopwatch timer = new Stopwatch()..start();
      f = getSuggestions(opts).then((List<Suggestion> suggestions) {
        _logger.finer(
          'code completion in ${timer.elapsedMilliseconds}ms, '
          '${suggestions.length} results'
        );
        return suggestions.map(suggestionToProxy).toList();
      }).catchError((error) {
        _logger.warning('Error retrieving code completions: ${error}');
        return <Suggestion>[];
      });
    }

    return new Promise.fromFuture(f).obj;
  }

  void _onDidInsertSuggestion(options) {
    if (_override != null && _override.hasShown) {
      _override.userSelection(jsObjectToDart(options['suggestion']));
      _override = null;
    } else {
      onDidInsertSuggestion(
        new TextEditor(options['editor']),
        new Point(options['triggerPosition']),
        jsObjectToDart(options['suggestion']));
    }
  }
}

class AutocompleteOptions {
  /// The current TextEditor.
  TextEditor editor;

  /// The position of the cursor.
  Point bufferPosition;

  // /// The scope descriptor for the current cursor position.
  // List<String> scopeDescriptor;

  /// The prefix for the word immediately preceding the current cursor position.
  String prefix;

  AutocompleteOptions(JsObject options) {
    editor = new TextEditor(options['editor']);
    bufferPosition = new Point(options['bufferPosition']);
    // scopeDescriptor = options['scopeDescriptor'];
    prefix = options['prefix'];
  }

  String toString() => '[${bufferPosition}, ${prefix}]';
}

class Suggestion {
  /// (required; or [snippet]): The text which will be inserted into the
  /// editor, in place of the prefix.
  String text;

  /// (required; or [text]): A snippet string. This will allow users to tab
  /// through function arguments or other options. e.g.
  /// `myFunction(${1:arg1}, ${2:arg2})`. See the snippets package for more
  /// information.
  String snippet;

  /// (optional): A string that will show in the UI for this suggestion. When
  /// not set, snippet || text is displayed. This is useful when snippet or text
  /// displays too much, and you want to simplify. e.g.
  /// `{type: 'attribute', snippet: 'class="$0"$1', displayText: 'class'}`
  String displayText;

  /// (optional): The text immediately preceding the cursor, which will be
  /// replaced by the text. If not provided, the prefix passed into
  /// `getSuggestions` will be used.
  String replacementPrefix;

  /// (optional): The suggestion type. It will be converted into an icon shown
  /// against the suggestion. Predefined styles exist for `variable`, `constant`,
  /// `property`, `value`, `method`, `function`, `class`, `type`, `keyword`,
  /// `tag`, `snippet`, `import`, `require`. This list represents nearly
  /// everything being colorized.
  final String type;

  /// (optional): This is shown before the suggestion. Useful for return values.
  final String leftLabel;

  /// (optional): Use this instead of [leftLabel] if you want to use html for the
  /// left label.
  final String leftLabelHTML;

  /// (optional): An indicator (e.g. function, variable) denoting the "kind" of
  /// suggestion this represents.
  final String rightLabel;

  /// (optional): Use this instead of [rightLabel] if you want to use html for
  /// the right label.
  final String rightLabelHTML;

  /// (optional): Class name for the suggestion in the suggestion list. Allows
  /// you to style your suggestion via CSS, if desired.
  final String className;

  /// (optional): If you want complete control over the icon shown against the
  /// suggestion. e.g. iconHTML: `<i class="icon-move-right"></i>`. The
  /// background color of the icon will still be determined (by default) from
  /// the type.
  final String iconHTML;

  /// (optional): A doc-string summary or short description of the suggestion.
  /// When specified, it will be displayed at the bottom of the suggestions list.
  final String description;

  /// (optional): A url to the documentation or more information about this
  /// suggestion. When specified, a `More...` link will be displayed in the
  /// description area.
  final String descriptionMoreURL;

  final String requiredImport;

  int selectionOffset;

  int itemIndex;

  Suggestion({this.text, this.snippet, this.displayText, this.replacementPrefix,
    this.type, this.leftLabel, this.leftLabelHTML, this.rightLabel, this.rightLabelHTML,
    this.className, this.iconHTML, this.description, this.descriptionMoreURL,
    this.requiredImport, this.selectionOffset, this.itemIndex});

  Map _toMap() {
    Map m = {};
    if (text != null) m['text'] = text;
    if (snippet != null) m['snippet'] = snippet;
    if (displayText != null) m['displayText'] = displayText;
    if (replacementPrefix != null) m['replacementPrefix'] = replacementPrefix;
    if (type != null) m['type'] = type;
    if (leftLabel != null) m['leftLabel'] = leftLabel;
    if (leftLabelHTML != null) m['leftLabelHTML'] = leftLabelHTML;
    if (rightLabel != null) m['rightLabel'] = rightLabel;
    if (rightLabelHTML != null) m['rightLabelHTML'] = rightLabelHTML;
    if (className != null) m['className'] = className;
    if (iconHTML != null) m['iconHTML'] = iconHTML;
    if (description != null) m['description'] = description;
    if (descriptionMoreURL != null) m['descriptionMoreURL'] = descriptionMoreURL;
    if (requiredImport != null) m['requiredImport'] = requiredImport;
    if (selectionOffset != null) m['selectionOffset'] = selectionOffset;
    if (itemIndex != null) m['itemIndex'] = itemIndex;
    return m;
  }

  JsObject _toProxy() => jsify(_toMap());
}

class _AutoCompleteOverride<T> {
  final TextEditor editor;
  final List<dynamic> items;
  final Function renderer;
  final Completer<T> completer = new Completer<T>();

  bool hasShown = false;

  _AutoCompleteOverride(this.editor, this.items, this.renderer);

  List<Suggestion> renderSuggestions() {
    List<Suggestion> result = [];
    for (int i = 0; i < items.length; i++) {
      Suggestion suggestion = renderer(items[i]);
      suggestion.itemIndex = i;
      result.add(suggestion);
    }
    return result;
  }

  void userSelection(Map selectedSuggestion) {
    int index = selectedSuggestion['itemIndex'];
    completer.complete(index == null ? null : items[index]);
  }

  Future<T> get future => completer.future;
}

class _AutoCompleteEditorOverride {
  final TextEditor editor;
  final AutoCompleter autoCompleter;

  _AutoCompleteEditorOverride(this.editor, this.autoCompleter);
}
