part of atom.linter_impl;

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

    _disposables.add(atom.config.observe(_infosPrefPath, null, regen));
    _disposables.add(atom.config.observe(_todosPrefPath, null, regen));

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
          '${issues.length - _maxIssuesPerFile + 1} additional issues not shown');
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
                'Maximum project issue count of ${_maxIssuesPerProject} hit.');
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
