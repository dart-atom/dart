part of atom.linter_impl;

// TODO: Show that an error has an associated quick-fix.

// TODO: We should cap on a per-project basis, rather than a per-workspace basis.

const int maxIssuesPerFile = 200;
const int maxTotalIssues = 500;

StreamController<List<AnalysisError>> _processedErrorsController = new StreamController.broadcast();

/// Consumes the atomlinter/linter self-service API.
class DartLinterConsumer extends LinterConsumer with Disposables {
  ErrorRepository _errorRepository;
  Duration _reportingDelay = new Duration(milliseconds: 750);
  DartLinterProvider _provider = new DartLinterProvider();
  LinterService _service;

  List<AnalysisError> _oldIssues = [];
  bool _displayedWarning = false;

  DartLinterConsumer(this._errorRepository) {
    var regen = (_) => _regenErrors();

    add(atom.config.observe(_infosPrefPath, null, regen));
    add(atom.config.observe(_todosPrefPath, null, regen));

    EventStream errorStream = new EventStream(
        _errorRepository.onChange).debounce(_reportingDelay);
    errorStream.listen((_) => _regenErrors());
  }

  void consume(LinterService service) {
    _service = service;
  }

  void _regenErrors() {
    // Get issues per file.
    Map<String, List<AnalysisError>> issuesMap = _errorRepository.knownErrors;
    List<AnalysisError> allIssues = [];

    issuesMap.forEach((String path, List<AnalysisError> issues) {
      issues = issues.toList()..sort(_errorComparer);
      issues = _filter(issues);
      if (issues.length > maxIssuesPerFile) {
        // Create an issue to say we capped the number of issues.
        AnalysisError first = issues.first;
        AnalysisError cap = new AnalysisError(first.severity, first.type,
          new Location(first.location.file, 0, 1, 1, 1),
          '${issues.length - maxIssuesPerFile + 1} additional issues not shown');
        issues = issues.sublist(0, maxIssuesPerFile - 1);
        issues.insert(0, cap);
      }
      allIssues.addAll(issues);
    });

    allIssues.sort(_errorComparer);

    if (allIssues.length > maxTotalIssues) {
      _warnMaxCap(allIssues);
      allIssues = allIssues.sublist(0, maxTotalIssues);
    }

    _emit(allIssues);
  }

  List _filter(List<AnalysisError> issues) {
    bool showInfos = _shouldShowInfoMessages();
    bool showTodos = _shouldShowTodosMessages();

    return issues.where((AnalysisError issue) {
      if (!showInfos && issue.severity == 'INFO') return false;
      if (!showTodos && issue.type == 'TODO') return false;

      return true;
    }).toList();
  }

  void _warnMaxCap(List issues) {
    if (_displayedWarning) return;
    _displayedWarning = true;
    atom.notifications.addWarning(
        'Warning: displaying ${maxTotalIssues} issues of ${issues.length} total.');
  }

  void _emit(List newIssues) {
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
}
