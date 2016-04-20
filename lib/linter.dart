library atom.linter_impl;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';

import 'analysis/analysis_server_lib.dart' show AnalysisError, Location;
import 'atom_linter.dart';
import 'error_repository.dart';
import 'impl/debounce.dart';
import 'state.dart' show pluginId;
import 'utils.dart';

Stream<List<AnalysisError>> get onProcessedErrorsChanged => _processedErrorsController.stream;

LintMessage _errorToLintMessage(String filePath, AnalysisError error) {
  String text = error.code == null ? error.message : '${error.message} (${error.code})';

  return new LintMessage(
      type: _severityMap[error.severity],
      text: text,
      filePath: filePath,
      range: _locationToRange(error.location));
}

Rn _locationToRange(Location location) {
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

String _configureErrorsPrefPath = '${pluginId}.configureErrorsView';

bool _shouldShowInfoMessages() {
  String pref = atom.config.getValue(_configureErrorsPrefPath);
  return pref == 'infos' || pref == 'todos';
}

bool _shouldShowTodosMessages() {
  String pref = atom.config.getValue(_configureErrorsPrefPath);
  return pref == 'todos';
}

/// This only class exists to provide linting information to atomlinter/linter.
class DartLinterProvider extends LinterProvider {
  DartLinterProvider() : super(grammarScopes: ['source.dart'], scope: 'project');

  void register() => LinterProvider.registerLinterProvider('provideLinter', this);

  /// This is a no-op.
  Future<List<LintMessage>> lint(TextEditor editor) => new Future.value([]);
}

const int _maxIssuesPerFile = 200;
const int _maxIssuesPerProject = 500;

StreamController<List<AnalysisError>> _processedErrorsController = new StreamController.broadcast();

/// Consumes the atomlinter/linter self-service API.
class DartLinterConsumer extends LinterConsumer implements Disposable {
  ErrorRepository _errorRepository;
  Duration _reportingDelay = new Duration(milliseconds: 750);
  DartLinterProvider _provider = new DartLinterProvider();
  LinterService _service;
  Disposables _disposables = new Disposables();

  List<AnalysisError> _oldIssues = [];

  DartLinterConsumer(this._errorRepository) {
    var regen = (_) => _regenErrors();

    _disposables.add(atom.config.observe(_configureErrorsPrefPath, null, regen));

    Stream errorStream = _errorRepository.onChange.transform(new Debounce(_reportingDelay));
    errorStream.listen(regen);
  }

  List<AnalysisError> get errors => _oldIssues;

  void consume(LinterService service) {
    _service = service;
  }

  void _regenErrors() {
    // Get issues per file.
    Map<String, List<AnalysisError>> issuesMap = _errorRepository.knownErrors;
    List<AnalysisError> allIssues = [];

    issuesMap.forEach((String path, List<AnalysisError> issues) {
      issues = _filter(issues)..sort(_errorComparer);
      if (issues.length > _maxIssuesPerFile) {
        // Create an issue to say we capped the number of issues.
        AnalysisError first = issues.first;
        AnalysisError cap = new AnalysisError(first.severity, first.type,
          new Location(first.location.file, 0, 1, 1, 1),
          '${issues.length - _maxIssuesPerFile + 1} additional issues not shown',
          null);
        issues = issues.sublist(0, _maxIssuesPerFile - 1);
        issues.insert(0, cap);
      }
      allIssues.addAll(issues);
    });

    allIssues.sort(_errorComparer);

    // If we have too many total issues, then crop them.
    List<String> projects = atom.project.getPaths();
    Map<String, int> projectErrorCount = {};

    if (allIssues.length > projects.length * _maxIssuesPerProject) {
      for (String project in projects) {
        projectErrorCount[project] = 0;
      }

      List<AnalysisError> newIssues = [];

      for (String project in projects) {
        for (AnalysisError issue in allIssues) {
          if (issue.location.file.startsWith(project)) {
            projectErrorCount[project]++;

            if (projectErrorCount[project] < _maxIssuesPerProject) {
              print(issue.severity + ' ' + issue.type);
              newIssues.add(issue);
            } else if (projectErrorCount[project] == _maxIssuesPerProject) {
              AnalysisError cap = new AnalysisError('ERROR', 'ERROR',
                new Location(issue.location.file, 0, 1, 1, 1),
                'Maximum project issue count of ${_maxIssuesPerProject} hit.',
                null);
              newIssues.add(cap);
            }
          }
        }
      }

      allIssues = newIssues;
      allIssues.sort(_errorComparer);
    }

    _emit(allIssues);
  }

  List<AnalysisError> _filter(List<AnalysisError> issues) {
    bool showInfos = _shouldShowInfoMessages();
    bool showTodos = _shouldShowTodosMessages();

    return issues.where((AnalysisError issue) {
      if (!showInfos && issue.severity == 'INFO') return false;
      if (!showTodos && issue.type == 'TODO') return false;
      if (issue.message.endsWith('cannot both be unnamed')) return false;

      return true;
    }).toList();
  }

  void _emit(List<AnalysisError> newIssues) {
    if (!listIdentical(_oldIssues, newIssues)) {
      _oldIssues = newIssues;

      _processedErrorsController.add(newIssues);

      if (_service != null) {
        _service.deleteMessages(_provider);
        _service.setMessages(_provider,
            newIssues.map((e) => _errorToLintMessage(e.location.file, e)).toList());
      }
    }
  }

  void dispose() => _disposables.dispose();
}
