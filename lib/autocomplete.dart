library autocomplete;

import 'dart:async';

import 'package:logging/logging.dart';

import 'analysis/analysis_server_gen.dart' show CompletionResults,
    CompletionSuggestion, SuggestionsResult;
import 'atom.dart';
import 'atom_autocomplete.dart';
import 'state.dart';

part 'autocomplete/dart_autocomplete_provider.dart';

final Logger _logger = new Logger('autocomplete');
