/// A library to manage launching applications.
library atom.launch;

import 'dart:async';
import 'dart:math' as math;

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../analysis/analysis_server_lib.dart' show CreateContextResult;
import '../analysis_server.dart';
import '../debug/debugger.dart';
import '../projects.dart';
import '../state.dart';
import '../utils.dart';
import 'launch_configs.dart';

export 'launch_configs.dart' show LaunchConfiguration;

final Logger _logger = new Logger('atom.launch');

final math.Random _rand = new math.Random();

/// This guesses for a likely open port. We could also use the technique of
/// opening a server socket, recording the port number, and closing the socket.
int getOpenPort() => 16161 + _rand.nextInt(100);

class LaunchManager implements Disposable {
  StreamController<Launch> _launchAdded = new StreamController.broadcast(sync: true);
  StreamController<Launch> _launchActivated = new StreamController.broadcast();
  StreamController<Launch> _launchTerminated = new StreamController.broadcast();
  StreamController<Launch> _launchRemoved = new StreamController.broadcast();

  List<LaunchType> launchTypes = [];

  Launch _activeLaunch;
  final List<Launch> _launches = [];

  LaunchManager();

  Launch get activeLaunch => _activeLaunch;

  List<Launch> get launches => _launches;

  void addLaunch(Launch launch) {
    _launches.add(launch);
    bool activated = false;

    // Automatically remove all dead launches.
    List<Launch> removed = [];
    _launches.removeWhere((Launch l) {
      if (l.isTerminated) {
        if (_activeLaunch == l) _activeLaunch = null;
        removed.add(l);
      }
      return l.isTerminated;
    });

    if (_activeLaunch == null) {
      _activeLaunch = launch;
      activated = true;
    }

    removed.forEach((l) => _launchRemoved.add(l));
    _launchAdded.add(launch);
    if (activated) _launchActivated.add(launch);
  }

  void setActiveLaunch(Launch launch) {
    if (launch != _activeLaunch) {
      _activeLaunch = launch;
      _launchActivated.add(_activeLaunch);
    }
  }

  void removeLaunch(Launch launch) {
    if (!_launches.contains(launch)) return;

    _launches.remove(launch);
    bool activeChanged = false;
    if (launch == _activeLaunch) {
      _activeLaunch = null;
      if (_launches.isNotEmpty) _activeLaunch = launches.first;
      activeChanged = true;
    }

    _launchRemoved.add(launch);
    if (activeChanged) _launchActivated.add(_activeLaunch);
  }

  Stream<Launch> get onLaunchAdded => _launchAdded.stream;
  Stream<Launch> get onLaunchActivated => _launchActivated.stream;
  Stream<Launch> get onLaunchTerminated => _launchTerminated.stream;
  Stream<Launch> get onLaunchRemoved => _launchRemoved.stream;

  void registerLaunchType(LaunchType type) {
    launchTypes.remove(type);
    launchTypes.add(type);
  }

  List<String> getLaunchTypes() =>
      launchTypes.map((LaunchType l) => l.type).toList()..sort();

  /// Get the best launch handler for the given resource; return `null` otherwise.
  LaunchType getHandlerFor(String path, LaunchData data) {
    if (path == null) return null;

    for (LaunchType type in launchTypes) {
      if (type.canLaunch(path, data)) return type;
    }

    return null;
  }

  LaunchType getLaunchType(String typeCode) {
    for (LaunchType type in launchTypes) {
      if (type.type == typeCode) return type;
    }
    return null;
  }

  List<Launchable> getAllLaunchables(String path, LaunchData data) {
    List<Launchable> results = [];

    for (LaunchType type in launchTypes) {
      if (type.canLaunch(path, data)) {
        DartProject project = projectManager.getProjectFor(path);
        if (project == null) continue;

        String relPath = project.getRelative(path);
        results.add(new Launchable(type, project.path, relPath));
      }
    }

    return results;
  }

  void dispose() {
    for (Launch launch in _launches.toList()) {
      launch.dispose();
    }
  }
}

/// A general type of launch, like a command-line launch or a web launch.
abstract class LaunchType {
  final String type;

  LaunchType(this.type);

  bool canLaunch(String path, LaunchData data);

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration);

  bool get supportsChecked => true;

  bool get supportsDebugArg => true;

  /// Return a yaml fragment with the defaults values for a new launch
  /// configuration.
  String getDefaultConfigText();

  bool operator== (obj) => obj is LaunchType && obj.type == type;

  int get hashCode => type.hashCode;

  String toString() => type;
}

class LaunchData {
  static final RegExp _mainRegex = new RegExp(r'main *\(');

  final String fileContents;

  bool _hasMain;

  LaunchData(this.fileContents);

  bool get hasMain {
    if (_hasMain == null) {
      if (fileContents != null) {
        _hasMain = fileContents.contains(_mainRegex);
      } else {
        _hasMain = false;
      }
    }

    return _hasMain;
  }
}

class Launchable {
  final LaunchType type;
  final String projectPath;
  final String relativePath;

  Launchable(this.type, this.projectPath, this.relativePath);

  String get path => fs.join(projectPath, relativePath);

  String getDisplayName() => '${relativePath} (${type})';

  operator ==(other) => other is Launchable && (type == other.type && relativePath == other.relativePath);

  int get hashCode => type.hashCode ^ (relativePath.hashCode << 37);

  String toString() => getDisplayName();
}

/// The instantiation of something that was launched.
class Launch implements Disposable {
  static int _id = 0;

  final LaunchType launchType;
  final LaunchConfiguration launchConfiguration;
  final String name;
  final String title;
  final String targetName;
  final LaunchManager manager;
  final int id = ++_id;
  /*@deprecated*/
  final Function killHandler;
  final String cwd;

  final Property<int> exitCode = new Property();
  final Property<int> servicePort = new Property();

  StreamController<TextFragment> _stdio = new StreamController.broadcast();
  DebugConnection _debugConnection;
  _PathResolver _pathResolver;

  Launch(this.manager, this.launchType, this.launchConfiguration, this.name, {
    this.killHandler,
    this.cwd,
    int servicePort,
    this.title,
    this.targetName
  }) {
    if (servicePort != null) this.servicePort.value = servicePort;
    if (cwd != null) _pathResolver = new _PathResolver(cwd);
  }

  bool get errored => exitCode.hasValue && exitCode.value != 0;

  DebugConnection get debugConnection => _debugConnection;

  bool get isRunning => exitCode.value == null;
  bool get isTerminated => exitCode.hasValue;

  bool get isActive => manager.activeLaunch == this;

  Stream<TextFragment> get onStdio => _stdio.stream;

  String get primaryResource => launchConfiguration.primaryResource;

  DartProject get project => projectManager.getProjectFor(primaryResource);

  String get locationLabel {
    if (cwd == null) return null;
    String home = fs.homedir;
    if (cwd.startsWith(home)) {
      return '~${cwd.substring(home.length)}';
    } else {
      return cwd;
    }
  }

  String get subtitle {
    List<String> desc = [];

    if (locationLabel != null) desc.add(locationLabel);
    if (launchConfiguration != null) {
      if (launchType != null) {
        if (launchType.supportsChecked && launchConfiguration.checked) desc.add('checked mode');
      }
      if (launchType.supportsDebugArg) {
        if (launchConfiguration.debug) desc.add('debug');
      }
    }

    return desc.isEmpty ? null : desc.join(' • ');
  }

  void pipeStdio(String str, {bool error: false, bool subtle: false, bool highlight: false}) {
    _stdio.add(new TextFragment(str, error: error, subtle: subtle, highlight: highlight));
  }

  bool canDebug() => isRunning && servicePort.hasValue;

  bool get hasDebugConnection => debugConnection != null;

  bool canKill() => killHandler != null;

  Future kill() {
    if (killHandler != null) {
      var f = killHandler();
      return f is Future ? f : new Future.value();
    } else {
      return new Future.value();
    }
  }

  bool get supportsRestart => false;

  Future restart({ bool fullRestart: false }) => new Future.error('unsupported');

  void launchTerminated(int code, {bool quiet: false}) {
    if (isTerminated) return;
    exitCode.value = code;

    if (_debugConnection != null) {
      debugManager.removeConnection(_debugConnection);
    }

    if (!quiet) {
      if (errored) {
        atom.notifications.addError('${this} exited with error code ${exitCode}.');
      } else {
        atom.notifications.addSuccess('${this} finished.');
      }
    }

    manager._launchTerminated.add(this);
  }

  Future<String> resolve(String url) {
    return _pathResolver != null ? _pathResolver.resolve(url) : new Future.value();
  }

  void addDebugConnection(DebugConnection connection) {
    this._debugConnection = connection;
    debugManager.addConnection(connection);
  }

  void dispose() {
    if (canKill() && !isRunning) {
      kill();
    }
  }

  String toString() => launchType != null ? '${launchType}: ${name}' : name;
}

class TextFragment {
  final String text;
  final bool error;
  final bool subtle;
  final bool highlight;

  TextFragment(this.text, {
    this.error: false, this.subtle: false, this.highlight: false
  });

  String toString() => text;
}

/// Use the analysis server to resolve urls. Cache the results so we don't issue
/// too many queries.
class CachingServerResolver implements _Resolver {
  _PathResolver _pathResolver;
  _ServerResolver _serverResolver;

  Map<String, String> _cache = {};

  CachingServerResolver({String cwd, AnalysisServer server}) {
    if (cwd != null) {
      _pathResolver = new _PathResolver(cwd);

      if (server.isActive) {
        _serverResolver = new _ServerResolver(cwd, server);
      }
    }
  }

  Future<String> resolve(String url) {
    if (_cache.containsKey(url)) {
      return new Future.value(_cache[url]);
    }

    return _resolve(url).then((result) {
      _cache[url] = result;
      return result;
    });
  }

  Future<String> _resolve(String url) async {
    if (_serverResolver != null && !url.startsWith('file:/') && url.contains(':')) {
      String result = await _serverResolver.resolve(url);
      if (result != null) return result;
      return _pathResolver?.resolve(url);
    } else if (_pathResolver != null) {
      return _pathResolver.resolve(url);
    } else {
      return new Future<String>.value();
    }
  }

  void dispose() {
    _pathResolver?.dispose();
    _serverResolver?.dispose();
  }
}

abstract class _Resolver implements Disposable {
  Future<String> resolve(String url);
}

class _PathResolver implements _Resolver {
  final String cwd;

  _PathResolver(this.cwd);

  Future<String> resolve(String url) {
    if (url.length < 2) return new Future.value();

    String path;

    if (url[0] == '/' || url[0] == fs.separator || url[1] == ':') {
      path = url;
    } else if (cwd != null) {
      path = fs.join(cwd, url);
    }

    if (path == null) return null;
    if (fs.existsSync(path)) return new Future.value(path);

    try {
      Uri uri = Uri.parse(url);
      if (uri.scheme == 'file') {
        path = uri.path;
        if (fs.existsSync(path)) return new Future.value(path);
      }
    } catch (_) { }

    return new Future.value();
  }

  void dispose() { }
}

class _ServerResolver implements _Resolver {
  final String path;
  final AnalysisServer server;

  Completer<String> _contextCompleter = new Completer();

  _ServerResolver(this.path, this.server) {
    analysisServer.server.execution.createContext(path).then((CreateContextResult result) {
      return _contextCompleter.complete(result.id);
    }).catchError((_) {
      return _contextCompleter.complete(null);
    });
  }

  Future<String> resolve(String url) async {
    String id = await _context;
    if (id == null) return null;

    try {
      return (await analysisServer.server.execution.mapUri(id, uri: url)).file;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _context.then((String id) {
      if (id != null) {
        analysisServer.server.execution.deleteContext(id).catchError((_) => null);
      }
    });
  }

  Future<String> get _context => _contextCompleter.future;
}
