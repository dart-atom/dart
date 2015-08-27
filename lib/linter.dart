library linter;

import 'dart:async';

import 'package:frappe/frappe.dart';

import 'atom.dart';
import 'atom_linter.dart';
import 'error_repository.dart';
import 'analysis/analysis_server_gen.dart' show AnalysisError, Location;
import 'state.dart' show pluginId;
import 'utils.dart';

part 'linter/dart_linter_consumer.dart';
part 'linter/dart_linter_provider.dart';

Stream<List<AnalysisError>> get onProcessedErrorsChanged => _processedErrorsController.stream;

LintMessage _errorToLintMessage(String filePath, AnalysisError error) {
  return new LintMessage(
      type: _severityMap[error.severity],
      text: error.message,
      filePath: filePath,
      range: _locationToRange(error.location));
}

Rn _locationToRange(Location location) {
  // TODO: This does not correctly handle multi-line errors.
  return new Rn(
      new Pt(location.startLine - 1, location.startColumn - 1),
      new Pt(location.startLine - 1, location.startColumn - 1 + location.length)
  );
}

int _errorComparer(AnalysisError a, AnalysisError b) {
  if (a.severity != b.severity) return _sev(b.severity) - _sev(a.severity);
  Location aloc = a.location;
  Location bloc = b.location;
  if (aloc.file != bloc.file) return aloc.file.compareTo(bloc.file);
  return aloc.offset - bloc.offset;
}

int _sev(String sev) {
  if (sev == 'ERROR') return 3;
  if (sev == 'WARNING') return 2;
  if (sev == 'INFO') return 1;
  return 0;
}

final Map<String, String> _severityMap = {
  'ERROR': LintMessage.ERROR,
  'WARNING': LintMessage.WARNING,
  'INFO': LintMessage.INFO
};

String _infosPrefPath = '${pluginId}.showInfos';
String _todosPrefPath = '${pluginId}.showTodos';
String _filterUnnamedLibraryWarningsPath = '${pluginId}.filterUnnamedLibraryWarnings';
String _filterCompiledToJSWarningsPath = '${pluginId}.filterCompiledToJSWarnings';

bool _shouldShowInfoMessages() => atom.config.getValue(_infosPrefPath);
bool _shouldShowTodosMessages() => atom.config.getValue(_todosPrefPath);
bool _shouldFilterUnnamedLibraryWarnings() =>
    atom.config.getValue(_filterUnnamedLibraryWarningsPath);
bool _shouldFilterCompiledToJSWarnings() =>
    atom.config.getValue(_filterCompiledToJSWarningsPath);
