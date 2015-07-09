part of linter;

/// Consumes the atomlinter/linter self-service API.
class DartLinterConsumer extends LinterConsumer with Disposables {
  ErrorRepository _errorRepository;
  //Duration _reportingDelay = new Duration(seconds: 1);
  DartLinterConsumer(this._errorRepository);

  consume(LinterService service) {
    var provider = new DartLinterProvider();
    var errorStream = new EventStream(_errorRepository.onChange); //.delay(_reportingDelay);

    errorStream.listen((_) {
      final acceptableErrorTypes = ['ERROR', 'WARNING'];
      if (_shouldShowInfoMessages()) acceptableErrorTypes.add('INFO');

      var allErrors =
          _errorRepository.knownErrors.values.expand((l) => l).toList();
      var sortedErrors = new List<AnalysisError>.from(allErrors)
        ..sort(_errorComparer);
      if (!_shouldShowTodosMessages()) {
        sortedErrors = sortedErrors.where((issue) => issue.type != 'TODO');
      }
      if (_showFilterUnnamedLibraryWarnings()) {
        sortedErrors = sortedErrors.where(
          (issue) => !issue.message.contains('cannot both be unnamed'));
      }

      var formattedErrors = sortedErrors
          .where((e) => acceptableErrorTypes.contains(e.severity))
          .map((e) => _errorToLintMessage(e.location.file, e))
          .toList();

      service.deleteMessages(provider);
      service.setMessages(provider, formattedErrors);
    });
  }
}
