// This is a generated file.

/// A library to access the analysis server API.
library atom.analysis_server_lib;

import 'dart:async';
import 'dart:convert' show JSON, JsonCodec;

import 'package:logging/logging.dart';

final Logger _logger = new Logger('analysis_server_lib');

/// @optional
const String optional = 'optional';

class Server {
  StreamSubscription _streamSub;
  Function _writeMessage;
  int _id = 0;
  Map<String, Completer> _completers = {};
  JsonCodec _jsonEncoder = new JsonCodec(toEncodable: _toEncodable);
  Map<String, Domain> _domains = {};
  StreamController _onSend = new StreamController.broadcast();
  StreamController _onReceive = new StreamController.broadcast();

  ServerDomain _server;
  AnalysisDomain _analysis;
  CompletionDomain _completion;
  SearchDomain _search;
  EditDomain _edit;
  ExecutionDomain _execution;

  Server(Stream<String> inStream, void writeMessage(String message)) {
    configure(inStream, writeMessage);

    _server = new ServerDomain(this);
    _analysis = new AnalysisDomain(this);
    _completion = new CompletionDomain(this);
    _search = new SearchDomain(this);
    _edit = new EditDomain(this);
    _execution = new ExecutionDomain(this);
  }

  ServerDomain get server => _server;
  AnalysisDomain get analysis => _analysis;
  CompletionDomain get completion => _completion;
  SearchDomain get search => _search;
  EditDomain get edit => _edit;
  ExecutionDomain get execution => _execution;

  Stream<String> get onSend => _onSend.stream;
  Stream<String> get onReceive => _onReceive.stream;

  void configure(Stream<String> inStream, void writeMessage(String message)) {
    dispose();

    _streamSub = inStream.listen(_processMessage);
    _writeMessage = writeMessage;
  }

  void dispose() {
    if (_streamSub != null) _streamSub.cancel();
    //_completers.values.forEach((c) => c.completeError('disposed'));
    _completers.clear();
  }

  void _processMessage(String message) {
    if (message.startsWith('Observatory listening on')) return;

    try {
      _onReceive.add(message);

      var json = JSON.decode(message);

      if (json['id'] == null) {
        // Handle a notification.
        String event = json['event'];
        String prefix = event.substring(0, event.indexOf('.'));
        if (_domains[prefix] == null) {
          _logger.severe('no domain for notification: ${message}');
        } else {
          _domains[prefix]._handleEvent(event, json['params']);
        }
      } else {
        Completer completer = _completers.remove(json['id']);

        if (completer == null) {
          _logger.severe('unmatched request response: ${message}');
        } else if (json['error'] != null) {
          completer.completeError(RequestError.parse(json['error']));
        } else {
          completer.complete(json['result']);
        }
      }
    } catch (e) {
      _logger.severe('unable to decode message: ${message}, ${e}');
    }
  }

  Future _call(String method, [Map args]) {
    String id = '${++_id}';
    _completers[id] = new Completer();
    Map m = {'id': id, 'method': method};
    if (args != null) m['params'] = args;
    String message = _jsonEncoder.encode(m);
    _onSend.add(message);
    _writeMessage(message);
    return _completers[id].future;
  }

  static dynamic _toEncodable(obj) => obj is Jsonable ? obj.toMap() : obj;
}

abstract class Domain {
  final Server server;
  final String name;

  Map<String, StreamController> _controllers = {};
  Map<String, Stream> _streams = {};

  Domain(this.server, this.name) {
    server._domains[name] = this;
  }

  Future _call(String method, [Map args]) => server._call(method, args);

  Stream<dynamic> _listen(String name, Function cvt) {
    if (_streams[name] == null) {
      _controllers[name] = new StreamController.broadcast();
      _streams[name] = _controllers[name].stream.map(cvt);
    }

    return _streams[name];
  }

  void _handleEvent(String name, dynamic event) {
    if (_controllers[name] != null) {
      _controllers[name].add(event);
    }
  }

  String toString() => 'Domain ${name}';
}

abstract class Jsonable {
  Map toMap();
}

Map _mapify(Map m) {
  Map copy = {};

  for (var key in m.keys) {
    var value = m[key];
    if (value != null) copy[key] = value;
  }

  return copy;
}

// server domain

class ServerDomain extends Domain {
  ServerDomain(Server server) : super(server, 'server');

  Stream<ServerConnected> get onConnected => _listen('server.connected', ServerConnected.parse);
  Stream<ServerError> get onError => _listen('server.error', ServerError.parse);
  Stream<ServerStatus> get onStatus => _listen('server.status', ServerStatus.parse);

  Future<VersionResult> getVersion() => _call('server.getVersion').then(VersionResult.parse);

  Future shutdown() => _call('server.shutdown');

  Future setSubscriptions(List<String> subscriptions) => _call('server.setSubscriptions', {'subscriptions': subscriptions});
}

class ServerConnected {
  static ServerConnected parse(Map m) => new ServerConnected(m['version']);

  final String version;

  ServerConnected(this.version);
}

class ServerError {
  static ServerError parse(Map m) => new ServerError(m['isFatal'], m['message'], m['stackTrace']);

  final bool isFatal;
  final String message;
  final String stackTrace;

  ServerError(this.isFatal, this.message, this.stackTrace);
}

class ServerStatus {
  static ServerStatus parse(Map m) => new ServerStatus(analysis: AnalysisStatus.parse(m['analysis']), pub: PubStatus.parse(m['pub']));

  @optional final AnalysisStatus analysis;
  @optional final PubStatus pub;

  ServerStatus({this.analysis, this.pub});
}

class VersionResult {
  static VersionResult parse(Map m) => new VersionResult(m['version']);

  final String version;

  VersionResult(this.version);
}

// analysis domain

class AnalysisDomain extends Domain {
  AnalysisDomain(Server server) : super(server, 'analysis');

  Stream<AnalysisAnalyzedFiles> get onAnalyzedFiles => _listen('analysis.analyzedFiles', AnalysisAnalyzedFiles.parse);
  Stream<AnalysisErrors> get onErrors => _listen('analysis.errors', AnalysisErrors.parse);
  Stream<AnalysisFlushResults> get onFlushResults => _listen('analysis.flushResults', AnalysisFlushResults.parse);
  Stream<AnalysisFolding> get onFolding => _listen('analysis.folding', AnalysisFolding.parse);
  Stream<AnalysisHighlights> get onHighlights => _listen('analysis.highlights', AnalysisHighlights.parse);
  Stream<AnalysisInvalidate> get onInvalidate => _listen('analysis.invalidate', AnalysisInvalidate.parse);
  Stream<AnalysisNavigation> get onNavigation => _listen('analysis.navigation', AnalysisNavigation.parse);
  Stream<AnalysisOccurrences> get onOccurrences => _listen('analysis.occurrences', AnalysisOccurrences.parse);
  Stream<AnalysisOutline> get onOutline => _listen('analysis.outline', AnalysisOutline.parse);
  Stream<AnalysisOverrides> get onOverrides => _listen('analysis.overrides', AnalysisOverrides.parse);

  Future<ErrorsResult> getErrors(String file) {
    Map m = {'file': file};
    return _call('analysis.getErrors', m).then(ErrorsResult.parse);
  }

  Future<HoverResult> getHover(String file, int offset) {
    Map m = {'file': file, 'offset': offset};
    return _call('analysis.getHover', m).then(HoverResult.parse);
  }

  Future<LibraryDependenciesResult> getLibraryDependencies() => _call('analysis.getLibraryDependencies').then(LibraryDependenciesResult.parse);

  Future<NavigationResult> getNavigation(String file, int offset, int length) {
    Map m = {'file': file, 'offset': offset, 'length': length};
    return _call('analysis.getNavigation', m).then(NavigationResult.parse);
  }

  Future reanalyze({List<String> roots}) {
    Map m = {};
    if (roots != null) m['roots'] = roots;
    return _call('analysis.reanalyze', m);
  }

  Future setAnalysisRoots(List<String> included, List<String> excluded, {Map<String, String> packageRoots}) {
    Map m = {'included': included, 'excluded': excluded};
    if (packageRoots != null) m['packageRoots'] = packageRoots;
    return _call('analysis.setAnalysisRoots', m);
  }

  Future setGeneralSubscriptions(List<String> subscriptions) => _call('analysis.setGeneralSubscriptions', {'subscriptions': subscriptions});

  Future setPriorityFiles(List<String> files) => _call('analysis.setPriorityFiles', {'files': files});

  Future setSubscriptions(Map<String, List<String>> subscriptions) => _call('analysis.setSubscriptions', {'subscriptions': subscriptions});

  Future updateContent(Map<String, dynamic> files) => _call('analysis.updateContent', {'files': files});

  Future updateOptions(AnalysisOptions options) => _call('analysis.updateOptions', {'options': options});
}

class AnalysisAnalyzedFiles {
  static AnalysisAnalyzedFiles parse(Map m) => new AnalysisAnalyzedFiles(m['directories']);

  final List<String> directories;

  AnalysisAnalyzedFiles(this.directories);
}

class AnalysisErrors {
  static AnalysisErrors parse(Map m) => new AnalysisErrors(m['file'], m['errors'] == null ? null : m['errors'].map((obj) => AnalysisError.parse(obj)).toList());

  final String file;
  final List<AnalysisError> errors;

  AnalysisErrors(this.file, this.errors);
}

class AnalysisFlushResults {
  static AnalysisFlushResults parse(Map m) => new AnalysisFlushResults(m['files']);

  final List<String> files;

  AnalysisFlushResults(this.files);
}

class AnalysisFolding {
  static AnalysisFolding parse(Map m) => new AnalysisFolding(m['file'], m['regions'] == null ? null : m['regions'].map((obj) => FoldingRegion.parse(obj)).toList());

  final String file;
  final List<FoldingRegion> regions;

  AnalysisFolding(this.file, this.regions);
}

class AnalysisHighlights {
  static AnalysisHighlights parse(Map m) => new AnalysisHighlights(m['file'], m['regions'] == null ? null : m['regions'].map((obj) => HighlightRegion.parse(obj)).toList());

  final String file;
  final List<HighlightRegion> regions;

  AnalysisHighlights(this.file, this.regions);
}

class AnalysisInvalidate {
  static AnalysisInvalidate parse(Map m) => new AnalysisInvalidate(m['file'], m['offset'], m['length'], m['delta']);

  final String file;
  final int offset;
  final int length;
  final int delta;

  AnalysisInvalidate(this.file, this.offset, this.length, this.delta);
}

class AnalysisNavigation {
  static AnalysisNavigation parse(Map m) => new AnalysisNavigation(m['file'], m['regions'] == null ? null : m['regions'].map((obj) => NavigationRegion.parse(obj)).toList(), m['targets'] == null ? null : m['targets'].map((obj) => NavigationTarget.parse(obj)).toList(), m['files']);

  final String file;
  final List<NavigationRegion> regions;
  final List<NavigationTarget> targets;
  final List<String> files;

  AnalysisNavigation(this.file, this.regions, this.targets, this.files);
}

class AnalysisOccurrences {
  static AnalysisOccurrences parse(Map m) => new AnalysisOccurrences(m['file'], m['occurrences'] == null ? null : m['occurrences'].map((obj) => Occurrences.parse(obj)).toList());

  final String file;
  final List<Occurrences> occurrences;

  AnalysisOccurrences(this.file, this.occurrences);
}

class AnalysisOutline {
  static AnalysisOutline parse(Map m) => new AnalysisOutline(m['file'], Outline.parse(m['outline']));

  final String file;
  final Outline outline;

  AnalysisOutline(this.file, this.outline);
}

class AnalysisOverrides {
  static AnalysisOverrides parse(Map m) => new AnalysisOverrides(m['file'], m['overrides'] == null ? null : m['overrides'].map((obj) => Override.parse(obj)).toList());

  final String file;
  final List<Override> overrides;

  AnalysisOverrides(this.file, this.overrides);
}

class ErrorsResult {
  static ErrorsResult parse(Map m) => new ErrorsResult(m['errors'] == null ? null : m['errors'].map((obj) => AnalysisError.parse(obj)).toList());

  final List<AnalysisError> errors;

  ErrorsResult(this.errors);
}

class HoverResult {
  static HoverResult parse(Map m) => new HoverResult(m['hovers'] == null ? null : m['hovers'].map((obj) => HoverInformation.parse(obj)).toList());

  final List<HoverInformation> hovers;

  HoverResult(this.hovers);
}

class LibraryDependenciesResult {
  static LibraryDependenciesResult parse(Map m) => new LibraryDependenciesResult(m['libraries'], m['packageMap']);

  final List<String> libraries;
  final Map<String, Map<String, List<String>>> packageMap;

  LibraryDependenciesResult(this.libraries, this.packageMap);
}

class NavigationResult {
  static NavigationResult parse(Map m) => new NavigationResult(m['files'], m['targets'] == null ? null : m['targets'].map((obj) => NavigationTarget.parse(obj)).toList(), m['regions'] == null ? null : m['regions'].map((obj) => NavigationRegion.parse(obj)).toList());

  final List<String> files;
  final List<NavigationTarget> targets;
  final List<NavigationRegion> regions;

  NavigationResult(this.files, this.targets, this.regions);
}

// completion domain

class CompletionDomain extends Domain {
  CompletionDomain(Server server) : super(server, 'completion');

  Stream<CompletionResults> get onResults => _listen('completion.results', CompletionResults.parse);

  Future<SuggestionsResult> getSuggestions(String file, int offset) {
    Map m = {'file': file, 'offset': offset};
    return _call('completion.getSuggestions', m).then(SuggestionsResult.parse);
  }
}

class CompletionResults {
  static CompletionResults parse(Map m) => new CompletionResults(m['id'], m['replacementOffset'], m['replacementLength'], m['results'] == null ? null : m['results'].map((obj) => CompletionSuggestion.parse(obj)).toList(), m['isLast']);

  final String id;
  final int replacementOffset;
  final int replacementLength;
  final List<CompletionSuggestion> results;
  final bool isLast;

  CompletionResults(this.id, this.replacementOffset, this.replacementLength, this.results, this.isLast);
}

class SuggestionsResult {
  static SuggestionsResult parse(Map m) => new SuggestionsResult(m['id']);

  final String id;

  SuggestionsResult(this.id);
}

// search domain

class SearchDomain extends Domain {
  SearchDomain(Server server) : super(server, 'search');

  Stream<SearchResults> get onResults => _listen('search.results', SearchResults.parse);

  Future<FindElementReferencesResult> findElementReferences(String file, int offset, bool includePotential) {
    Map m = {'file': file, 'offset': offset, 'includePotential': includePotential};
    return _call('search.findElementReferences', m).then(FindElementReferencesResult.parse);
  }

  Future<FindMemberDeclarationsResult> findMemberDeclarations(String name) {
    Map m = {'name': name};
    return _call('search.findMemberDeclarations', m).then(FindMemberDeclarationsResult.parse);
  }

  Future<FindMemberReferencesResult> findMemberReferences(String name) {
    Map m = {'name': name};
    return _call('search.findMemberReferences', m).then(FindMemberReferencesResult.parse);
  }

  Future<FindTopLevelDeclarationsResult> findTopLevelDeclarations(String pattern) {
    Map m = {'pattern': pattern};
    return _call('search.findTopLevelDeclarations', m).then(FindTopLevelDeclarationsResult.parse);
  }

  Future<TypeHierarchyResult> getTypeHierarchy(String file, int offset) {
    Map m = {'file': file, 'offset': offset};
    return _call('search.getTypeHierarchy', m).then(TypeHierarchyResult.parse);
  }
}

class SearchResults {
  static SearchResults parse(Map m) => new SearchResults(m['id'], m['results'] == null ? null : m['results'].map((obj) => SearchResult.parse(obj)).toList(), m['isLast']);

  final String id;
  final List<SearchResult> results;
  final bool isLast;

  SearchResults(this.id, this.results, this.isLast);
}

class FindElementReferencesResult {
  static FindElementReferencesResult parse(Map m) => new FindElementReferencesResult(id: m['id'], element: Element.parse(m['element']));

  @optional final String id;
  @optional final Element element;

  FindElementReferencesResult({this.id, this.element});
}

class FindMemberDeclarationsResult {
  static FindMemberDeclarationsResult parse(Map m) => new FindMemberDeclarationsResult(m['id']);

  final String id;

  FindMemberDeclarationsResult(this.id);
}

class FindMemberReferencesResult {
  static FindMemberReferencesResult parse(Map m) => new FindMemberReferencesResult(m['id']);

  final String id;

  FindMemberReferencesResult(this.id);
}

class FindTopLevelDeclarationsResult {
  static FindTopLevelDeclarationsResult parse(Map m) => new FindTopLevelDeclarationsResult(m['id']);

  final String id;

  FindTopLevelDeclarationsResult(this.id);
}

class TypeHierarchyResult {
  static TypeHierarchyResult parse(Map m) => new TypeHierarchyResult(hierarchyItems: m['hierarchyItems'] == null ? null : m['hierarchyItems'].map((obj) => TypeHierarchyItem.parse(obj)).toList());

  @optional final List<TypeHierarchyItem> hierarchyItems;

  TypeHierarchyResult({this.hierarchyItems});
}

// edit domain

class EditDomain extends Domain {
  EditDomain(Server server) : super(server, 'edit');

  Future<FormatResult> format(String file, int selectionOffset, int selectionLength, {int lineLength}) {
    Map m = {'file': file, 'selectionOffset': selectionOffset, 'selectionLength': selectionLength};
    if (lineLength != null) m['lineLength'] = lineLength;
    return _call('edit.format', m).then(FormatResult.parse);
  }

  Future<AssistsResult> getAssists(String file, int offset, int length) {
    Map m = {'file': file, 'offset': offset, 'length': length};
    return _call('edit.getAssists', m).then(AssistsResult.parse);
  }

  Future<AvailableRefactoringsResult> getAvailableRefactorings(String file, int offset, int length) {
    Map m = {'file': file, 'offset': offset, 'length': length};
    return _call('edit.getAvailableRefactorings', m).then(AvailableRefactoringsResult.parse);
  }

  Future<FixesResult> getFixes(String file, int offset) {
    Map m = {'file': file, 'offset': offset};
    return _call('edit.getFixes', m).then(FixesResult.parse);
  }

  Future<RefactoringResult> getRefactoring(String kind, String file, int offset, int length, bool validateOnly, {RefactoringOptions options}) {
    Map m = {'kind': kind, 'file': file, 'offset': offset, 'length': length, 'validateOnly': validateOnly};
    if (options != null) m['options'] = options;
    return _call('edit.getRefactoring', m).then(RefactoringResult.parse);
  }

  Future<SortMembersResult> sortMembers(String file) {
    Map m = {'file': file};
    return _call('edit.sortMembers', m).then(SortMembersResult.parse);
  }

  Future<OrganizeDirectivesResult> organizeDirectives(String file) {
    Map m = {'file': file};
    return _call('edit.organizeDirectives', m).then(OrganizeDirectivesResult.parse);
  }
}

class FormatResult {
  static FormatResult parse(Map m) => new FormatResult(m['edits'] == null ? null : m['edits'].map((obj) => SourceEdit.parse(obj)).toList(), m['selectionOffset'], m['selectionLength']);

  final List<SourceEdit> edits;
  final int selectionOffset;
  final int selectionLength;

  FormatResult(this.edits, this.selectionOffset, this.selectionLength);
}

class AssistsResult {
  static AssistsResult parse(Map m) => new AssistsResult(m['assists'] == null ? null : m['assists'].map((obj) => SourceChange.parse(obj)).toList());

  final List<SourceChange> assists;

  AssistsResult(this.assists);
}

class AvailableRefactoringsResult {
  static AvailableRefactoringsResult parse(Map m) => new AvailableRefactoringsResult(m['kinds']);

  final List<String> kinds;

  AvailableRefactoringsResult(this.kinds);
}

class FixesResult {
  static FixesResult parse(Map m) => new FixesResult(m['fixes'] == null ? null : m['fixes'].map((obj) => AnalysisErrorFixes.parse(obj)).toList());

  final List<AnalysisErrorFixes> fixes;

  FixesResult(this.fixes);
}

class RefactoringResult {
  static RefactoringResult parse(Map m) => new RefactoringResult(m['initialProblems'] == null ? null : m['initialProblems'].map((obj) => RefactoringProblem.parse(obj)).toList(), m['optionsProblems'] == null ? null : m['optionsProblems'].map((obj) => RefactoringProblem.parse(obj)).toList(), m['finalProblems'] == null ? null : m['finalProblems'].map((obj) => RefactoringProblem.parse(obj)).toList(), feedback: RefactoringFeedback.parse(m['feedback']), change: SourceChange.parse(m['change']), potentialEdits: m['potentialEdits']);

  final List<RefactoringProblem> initialProblems;
  final List<RefactoringProblem> optionsProblems;
  final List<RefactoringProblem> finalProblems;
  @optional final RefactoringFeedback feedback;
  @optional final SourceChange change;
  @optional final List<String> potentialEdits;

  RefactoringResult(this.initialProblems, this.optionsProblems, this.finalProblems, {this.feedback, this.change, this.potentialEdits});
}

class SortMembersResult {
  static SortMembersResult parse(Map m) => new SortMembersResult(SourceFileEdit.parse(m['edit']));

  final SourceFileEdit edit;

  SortMembersResult(this.edit);
}

class OrganizeDirectivesResult {
  static OrganizeDirectivesResult parse(Map m) => new OrganizeDirectivesResult(SourceFileEdit.parse(m['edit']));

  final SourceFileEdit edit;

  OrganizeDirectivesResult(this.edit);
}

// execution domain

class ExecutionDomain extends Domain {
  ExecutionDomain(Server server) : super(server, 'execution');

  Stream<ExecutionLaunchData> get onLaunchData => _listen('execution.launchData', ExecutionLaunchData.parse);

  Future<CreateContextResult> createContext(String contextRoot) {
    Map m = {'contextRoot': contextRoot};
    return _call('execution.createContext', m).then(CreateContextResult.parse);
  }

  Future deleteContext(String id) => _call('execution.deleteContext', {'id': id});

  Future<MapUriResult> mapUri(String id, {String file, String uri}) {
    Map m = {'id': id};
    if (file != null) m['file'] = file;
    if (uri != null) m['uri'] = uri;
    return _call('execution.mapUri', m).then(MapUriResult.parse);
  }

  Future setSubscriptions(List<String> subscriptions) => _call('execution.setSubscriptions', {'subscriptions': subscriptions});
}

class ExecutionLaunchData {
  static ExecutionLaunchData parse(Map m) => new ExecutionLaunchData(m['file'], kind: m['kind'], referencedFiles: m['referencedFiles']);

  final String file;
  @optional final String kind;
  @optional final List<String> referencedFiles;

  ExecutionLaunchData(this.file, {this.kind, this.referencedFiles});
}

class CreateContextResult {
  static CreateContextResult parse(Map m) => new CreateContextResult(m['id']);

  final String id;

  CreateContextResult(this.id);
}

class MapUriResult {
  static MapUriResult parse(Map m) => new MapUriResult(file: m['file'], uri: m['uri']);

  @optional final String file;
  @optional final String uri;

  MapUriResult({this.file, this.uri});
}

// type definitions


class AddContentOverlay implements Jsonable {
  static AddContentOverlay parse(Map m) {
    if (m == null) return null;
    return new AddContentOverlay(m['type'], m['content']);
  }

  final String type;
  final String content;

  Map toMap() => _mapify({'type': type, 'content': content});

  AddContentOverlay(this.type, this.content);
}

class AnalysisError {
  static AnalysisError parse(Map m) {
    if (m == null) return null;
    return new AnalysisError(m['severity'], m['type'], Location.parse(m['location']), m['message'], correction: m['correction']);
  }

  final String severity;
  final String type;
  final Location location;
  final String message;
  @optional final String correction;

  AnalysisError(this.severity, this.type, this.location, this.message, {this.correction});

  operator==(o) => o is AnalysisError && severity == o.severity && type == o.type && location == o.location && message == o.message && correction == o.correction;

  get hashCode => severity.hashCode ^ type.hashCode ^ location.hashCode ^ message.hashCode;

  String toString() => '[AnalysisError severity: ${severity}, type: ${type}, location: ${location}, message: ${message}]';
}

class AnalysisErrorFixes {
  static AnalysisErrorFixes parse(Map m) {
    if (m == null) return null;
    return new AnalysisErrorFixes(AnalysisError.parse(m['error']), m['fixes'] == null ? null : m['fixes'].map((obj) => SourceChange.parse(obj)).toList());
  }

  final AnalysisError error;
  final List<SourceChange> fixes;

  AnalysisErrorFixes(this.error, this.fixes);
}

class AnalysisOptions implements Jsonable {
  static AnalysisOptions parse(Map m) {
    if (m == null) return null;
    return new AnalysisOptions(enableAsync: m['enableAsync'], enableDeferredLoading: m['enableDeferredLoading'], enableEnums: m['enableEnums'], enableNullAwareOperators: m['enableNullAwareOperators'], enableSuperMixins: m['enableSuperMixins'], generateDart2jsHints: m['generateDart2jsHints'], generateHints: m['generateHints'], generateLints: m['generateLints']);
  }

  @optional final bool enableAsync;
  @optional final bool enableDeferredLoading;
  @optional final bool enableEnums;
  @optional final bool enableNullAwareOperators;
  @optional final bool enableSuperMixins;
  @optional final bool generateDart2jsHints;
  @optional final bool generateHints;
  @optional final bool generateLints;

  Map toMap() => _mapify({'enableAsync': enableAsync, 'enableDeferredLoading': enableDeferredLoading, 'enableEnums': enableEnums, 'enableNullAwareOperators': enableNullAwareOperators, 'enableSuperMixins': enableSuperMixins, 'generateDart2jsHints': generateDart2jsHints, 'generateHints': generateHints, 'generateLints': generateLints});

  AnalysisOptions({this.enableAsync, this.enableDeferredLoading, this.enableEnums, this.enableNullAwareOperators, this.enableSuperMixins, this.generateDart2jsHints, this.generateHints, this.generateLints});
}

class AnalysisStatus {
  static AnalysisStatus parse(Map m) {
    if (m == null) return null;
    return new AnalysisStatus(m['isAnalyzing'], analysisTarget: m['analysisTarget']);
  }

  final bool isAnalyzing;
  @optional final String analysisTarget;

  AnalysisStatus(this.isAnalyzing, {this.analysisTarget});
}

class ChangeContentOverlay implements Jsonable {
  static ChangeContentOverlay parse(Map m) {
    if (m == null) return null;
    return new ChangeContentOverlay(m['type'], m['edits'] == null ? null : m['edits'].map((obj) => SourceEdit.parse(obj)).toList());
  }

  final String type;
  final List<SourceEdit> edits;

  Map toMap() => _mapify({'type': type, 'edits': edits});

  ChangeContentOverlay(this.type, this.edits);
}

class CompletionSuggestion {
  static CompletionSuggestion parse(Map m) {
    if (m == null) return null;
    return new CompletionSuggestion(m['kind'], m['relevance'], m['completion'], m['selectionOffset'], m['selectionLength'], m['isDeprecated'], m['isPotential'], docSummary: m['docSummary'], docComplete: m['docComplete'], declaringType: m['declaringType'], element: Element.parse(m['element']), returnType: m['returnType'], parameterNames: m['parameterNames'], parameterTypes: m['parameterTypes'], requiredParameterCount: m['requiredParameterCount'], hasNamedParameters: m['hasNamedParameters'], parameterName: m['parameterName'], parameterType: m['parameterType'], importUri: m['importUri']);
  }

  final String kind;
  final int relevance;
  final String completion;
  final int selectionOffset;
  final int selectionLength;
  final bool isDeprecated;
  final bool isPotential;
  @optional final String docSummary;
  @optional final String docComplete;
  @optional final String declaringType;
  @optional final Element element;
  @optional final String returnType;
  @optional final List<String> parameterNames;
  @optional final List<String> parameterTypes;
  @optional final int requiredParameterCount;
  @optional final bool hasNamedParameters;
  @optional final String parameterName;
  @optional final String parameterType;
  @optional final String importUri;

  CompletionSuggestion(this.kind, this.relevance, this.completion, this.selectionOffset, this.selectionLength, this.isDeprecated, this.isPotential, {this.docSummary, this.docComplete, this.declaringType, this.element, this.returnType, this.parameterNames, this.parameterTypes, this.requiredParameterCount, this.hasNamedParameters, this.parameterName, this.parameterType, this.importUri});

  String toString() => '[CompletionSuggestion kind: ${kind}, relevance: ${relevance}, completion: ${completion}, selectionOffset: ${selectionOffset}, selectionLength: ${selectionLength}, isDeprecated: ${isDeprecated}, isPotential: ${isPotential}]';
}

class Element {
  static Element parse(Map m) {
    if (m == null) return null;
    return new Element(m['kind'], m['name'], m['flags'], location: Location.parse(m['location']), parameters: m['parameters'], returnType: m['returnType'], typeParameters: m['typeParameters']);
  }

  final String kind;
  final String name;
  final int flags;
  @optional final Location location;
  @optional final String parameters;
  @optional final String returnType;
  @optional final String typeParameters;

  Element(this.kind, this.name, this.flags, {this.location, this.parameters, this.returnType, this.typeParameters});

  String toString() => '[Element kind: ${kind}, name: ${name}, flags: ${flags}]';
}

class ExecutableFile {
  static ExecutableFile parse(Map m) {
    if (m == null) return null;
    return new ExecutableFile(m['file'], m['kind']);
  }

  final String file;
  final String kind;

  ExecutableFile(this.file, this.kind);
}

class FoldingRegion {
  static FoldingRegion parse(Map m) {
    if (m == null) return null;
    return new FoldingRegion(m['kind'], m['offset'], m['length']);
  }

  final String kind;
  final int offset;
  final int length;

  FoldingRegion(this.kind, this.offset, this.length);
}

class HighlightRegion {
  static HighlightRegion parse(Map m) {
    if (m == null) return null;
    return new HighlightRegion(m['type'], m['offset'], m['length']);
  }

  final String type;
  final int offset;
  final int length;

  HighlightRegion(this.type, this.offset, this.length);
}

class HoverInformation {
  static HoverInformation parse(Map m) {
    if (m == null) return null;
    return new HoverInformation(m['offset'], m['length'], containingLibraryPath: m['containingLibraryPath'], containingLibraryName: m['containingLibraryName'], containingClassDescription: m['containingClassDescription'], dartdoc: m['dartdoc'], elementDescription: m['elementDescription'], elementKind: m['elementKind'], parameter: m['parameter'], propagatedType: m['propagatedType'], staticType: m['staticType']);
  }

  final int offset;
  final int length;
  @optional final String containingLibraryPath;
  @optional final String containingLibraryName;
  @optional final String containingClassDescription;
  @optional final String dartdoc;
  @optional final String elementDescription;
  @optional final String elementKind;
  @optional final String parameter;
  @optional final String propagatedType;
  @optional final String staticType;

  HoverInformation(this.offset, this.length, {this.containingLibraryPath, this.containingLibraryName, this.containingClassDescription, this.dartdoc, this.elementDescription, this.elementKind, this.parameter, this.propagatedType, this.staticType});
}

class LinkedEditGroup {
  static LinkedEditGroup parse(Map m) {
    if (m == null) return null;
    return new LinkedEditGroup(m['positions'] == null ? null : m['positions'].map((obj) => Position.parse(obj)).toList(), m['length'], m['suggestions'] == null ? null : m['suggestions'].map((obj) => LinkedEditSuggestion.parse(obj)).toList());
  }

  final List<Position> positions;
  final int length;
  final List<LinkedEditSuggestion> suggestions;

  LinkedEditGroup(this.positions, this.length, this.suggestions);

  String toString() => '[LinkedEditGroup positions: ${positions}, length: ${length}, suggestions: ${suggestions}]';
}

class LinkedEditSuggestion {
  static LinkedEditSuggestion parse(Map m) {
    if (m == null) return null;
    return new LinkedEditSuggestion(m['value'], m['kind']);
  }

  final String value;
  final String kind;

  LinkedEditSuggestion(this.value, this.kind);
}

class Location {
  static Location parse(Map m) {
    if (m == null) return null;
    return new Location(m['file'], m['offset'], m['length'], m['startLine'], m['startColumn']);
  }

  final String file;
  final int offset;
  final int length;
  final int startLine;
  final int startColumn;

  Location(this.file, this.offset, this.length, this.startLine, this.startColumn);

  operator==(o) => o is Location && file == o.file && offset == o.offset && length == o.length && startLine == o.startLine && startColumn == o.startColumn;

  get hashCode => file.hashCode ^ offset.hashCode ^ length.hashCode ^ startLine.hashCode ^ startColumn.hashCode;

  String toString() => '[Location file: ${file}, offset: ${offset}, length: ${length}, startLine: ${startLine}, startColumn: ${startColumn}]';
}

class NavigationRegion {
  static NavigationRegion parse(Map m) {
    if (m == null) return null;
    return new NavigationRegion(m['offset'], m['length'], m['targets']);
  }

  final int offset;
  final int length;
  final List<int> targets;

  NavigationRegion(this.offset, this.length, this.targets);

  String toString() => '[NavigationRegion offset: ${offset}, length: ${length}, targets: ${targets}]';
}

class NavigationTarget {
  static NavigationTarget parse(Map m) {
    if (m == null) return null;
    return new NavigationTarget(m['kind'], m['fileIndex'], m['offset'], m['length'], m['startLine'], m['startColumn']);
  }

  final String kind;
  final int fileIndex;
  final int offset;
  final int length;
  final int startLine;
  final int startColumn;

  NavigationTarget(this.kind, this.fileIndex, this.offset, this.length, this.startLine, this.startColumn);

  String toString() => '[NavigationTarget kind: ${kind}, fileIndex: ${fileIndex}, offset: ${offset}, length: ${length}, startLine: ${startLine}, startColumn: ${startColumn}]';
}

class Occurrences {
  static Occurrences parse(Map m) {
    if (m == null) return null;
    return new Occurrences(Element.parse(m['element']), m['offsets'], m['length']);
  }

  final Element element;
  final List<int> offsets;
  final int length;

  Occurrences(this.element, this.offsets, this.length);
}

class Outline {
  static Outline parse(Map m) {
    if (m == null) return null;
    return new Outline(Element.parse(m['element']), m['offset'], m['length'], children: m['children'] == null ? null : m['children'].map((obj) => Outline.parse(obj)).toList());
  }

  final Element element;
  final int offset;
  final int length;
  @optional final List<Outline> children;

  Outline(this.element, this.offset, this.length, {this.children});
}

class Override {
  static Override parse(Map m) {
    if (m == null) return null;
    return new Override(m['offset'], m['length'], superclassMember: OverriddenMember.parse(m['superclassMember']), interfaceMembers: m['interfaceMembers'] == null ? null : m['interfaceMembers'].map((obj) => OverriddenMember.parse(obj)).toList());
  }

  final int offset;
  final int length;
  @optional final OverriddenMember superclassMember;
  @optional final List<OverriddenMember> interfaceMembers;

  Override(this.offset, this.length, {this.superclassMember, this.interfaceMembers});
}

class OverriddenMember {
  static OverriddenMember parse(Map m) {
    if (m == null) return null;
    return new OverriddenMember(Element.parse(m['element']), m['className']);
  }

  final Element element;
  final String className;

  OverriddenMember(this.element, this.className);
}

class Position {
  static Position parse(Map m) {
    if (m == null) return null;
    return new Position(m['file'], m['offset']);
  }

  final String file;
  final int offset;

  Position(this.file, this.offset);

  String toString() => '[Position file: ${file}, offset: ${offset}]';
}

class PubStatus {
  static PubStatus parse(Map m) {
    if (m == null) return null;
    return new PubStatus(m['isListingPackageDirs']);
  }

  final bool isListingPackageDirs;

  PubStatus(this.isListingPackageDirs);

  String toString() => '[PubStatus isListingPackageDirs: ${isListingPackageDirs}]';
}

class RefactoringMethodParameter {
  static RefactoringMethodParameter parse(Map m) {
    if (m == null) return null;
    return new RefactoringMethodParameter(m['kind'], m['type'], m['name'], id: m['id'], parameters: m['parameters']);
  }

  final String kind;
  final String type;
  final String name;
  @optional final String id;
  @optional final String parameters;

  RefactoringMethodParameter(this.kind, this.type, this.name, {this.id, this.parameters});
}

class RefactoringFeedback {
  static RefactoringFeedback parse(Map m) {
    if (m == null) return null;
    return new RefactoringFeedback();
  }

  RefactoringFeedback();
}

class RefactoringOptions implements Jsonable {
  static RefactoringOptions parse(Map m) {
    if (m == null) return null;
    return new RefactoringOptions();
  }

  Map toMap() => _mapify({});

  RefactoringOptions();
}

class RefactoringProblem {
  static RefactoringProblem parse(Map m) {
    if (m == null) return null;
    return new RefactoringProblem(m['severity'], m['message'], location: Location.parse(m['location']));
  }

  final String severity;
  final String message;
  @optional final Location location;

  RefactoringProblem(this.severity, this.message, {this.location});
}

class RemoveContentOverlay implements Jsonable {
  static RemoveContentOverlay parse(Map m) {
    if (m == null) return null;
    return new RemoveContentOverlay(m['type']);
  }

  final String type;

  Map toMap() => _mapify({'type': type});

  RemoveContentOverlay(this.type);
}

class RequestError {
  static RequestError parse(Map m) {
    if (m == null) return null;
    return new RequestError(m['code'], m['message'], stackTrace: m['stackTrace']);
  }

  final String code;
  final String message;
  @optional final String stackTrace;

  RequestError(this.code, this.message, {this.stackTrace});

  String toString() => '[RequestError code: ${code}, message: ${message}]';
}

class SearchResult {
  static SearchResult parse(Map m) {
    if (m == null) return null;
    return new SearchResult(Location.parse(m['location']), m['kind'], m['isPotential'], m['path'] == null ? null : m['path'].map((obj) => Element.parse(obj)).toList());
  }

  final Location location;
  final String kind;
  final bool isPotential;
  final List<Element> path;

  SearchResult(this.location, this.kind, this.isPotential, this.path);

  String toString() => '[SearchResult location: ${location}, kind: ${kind}, isPotential: ${isPotential}, path: ${path}]';
}

class SourceChange {
  static SourceChange parse(Map m) {
    if (m == null) return null;
    return new SourceChange(m['message'], m['edits'] == null ? null : m['edits'].map((obj) => SourceFileEdit.parse(obj)).toList(), m['linkedEditGroups'] == null ? null : m['linkedEditGroups'].map((obj) => LinkedEditGroup.parse(obj)).toList(), selection: Position.parse(m['selection']));
  }

  final String message;
  final List<SourceFileEdit> edits;
  final List<LinkedEditGroup> linkedEditGroups;
  @optional final Position selection;

  SourceChange(this.message, this.edits, this.linkedEditGroups, {this.selection});

  String toString() => '[SourceChange message: ${message}, edits: ${edits}, linkedEditGroups: ${linkedEditGroups}]';
}

class SourceEdit implements Jsonable {
  static SourceEdit parse(Map m) {
    if (m == null) return null;
    return new SourceEdit(m['offset'], m['length'], m['replacement'], id: m['id']);
  }

  final int offset;
  final int length;
  final String replacement;
  @optional final String id;

  Map toMap() => _mapify({'offset': offset, 'length': length, 'replacement': replacement, 'id': id});

  SourceEdit(this.offset, this.length, this.replacement, {this.id});

  String toString() => '[SourceEdit offset: ${offset}, length: ${length}, replacement: ${replacement}]';
}

class SourceFileEdit {
  static SourceFileEdit parse(Map m) {
    if (m == null) return null;
    return new SourceFileEdit(m['file'], m['fileStamp'], m['edits'] == null ? null : m['edits'].map((obj) => SourceEdit.parse(obj)).toList());
  }

  final String file;
  final int fileStamp;
  final List<SourceEdit> edits;

  SourceFileEdit(this.file, this.fileStamp, this.edits);

  String toString() => '[SourceFileEdit file: ${file}, fileStamp: ${fileStamp}, edits: ${edits}]';
}

class TypeHierarchyItem {
  static TypeHierarchyItem parse(Map m) {
    if (m == null) return null;
    return new TypeHierarchyItem(Element.parse(m['classElement']), m['interfaces'], m['mixins'], m['subclasses'], displayName: m['displayName'], memberElement: Element.parse(m['memberElement']), superclass: m['superclass']);
  }

  final Element classElement;
  final List<int> interfaces;
  final List<int> mixins;
  final List<int> subclasses;
  @optional final String displayName;
  @optional final Element memberElement;
  @optional final int superclass;

  TypeHierarchyItem(this.classElement, this.interfaces, this.mixins, this.subclasses, {this.displayName, this.memberElement, this.superclass});
}
