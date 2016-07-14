/// A library to manage launch configurations.
library atom.launch_configs;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';

import '../projects.dart';
import '../state.dart';

final Logger _logger = new Logger('atom.launch_configs');

// TODO: We need to update the launch configs in place - not create new objects.

// TODO: Watch the directory; update on changes.

class LaunchConfigurationManager implements Disposable, StateStorable {
  Map<String, _ProjectConfigurations> _projectConfigs = {};
  Map<String, int> _launchTimestamps = <String, int>{};

  StreamController _changeController = new StreamController.broadcast();

  LaunchConfigurationManager() {
    state.registerStorable('launchConfigs', this);

    projectManager.projects.forEach(_handleProjectAdded);
    projectManager.onProjectAdd.listen(_handleProjectAdded);
    projectManager.onProjectRemove.listen(_handleProjectRemoved);
  }

  /// Get all the launch configurations for the given project path.
  ///
  /// This method can be expensive.
  List<LaunchConfiguration> getConfigsForProject(String path) {
    if (path == null) return [];
    return _getCreateProjectConfig(path).getConfigs();
  }

  List<LaunchConfiguration> getAllConfigs() {
    return _projectConfigs.values
      .expand((_ProjectConfigurations configs) => configs.getConfigs())
      .toList();
  }

  /// Create a new launch configuration for the [projectPath] project. Use the
  /// given type and primaryResource. [primaryResource] should be relative to
  /// the project path. [defaultTypeParams] should be a fragment of yaml text.
  LaunchConfiguration createNewConfig(
    String projectPath,
    String type,
    String primaryResource,
    String defaultTypeParams
  ) {
    String content =
      '# ${toTitleCase(type)} launch configuration for ${primaryResource}.\n'
      'type: ${type}\n'
      'path: ${primaryResource}\n\n'
      '';
    if (defaultTypeParams != null) {
      content += '${type}:\n  ' + defaultTypeParams.replaceAll('\n', '\n  ');
    }
    content = content.trim() + '\n';

    _ProjectConfigurations configs = _getCreateProjectConfig(projectPath);
    String name = fs.basename(primaryResource);
    if (name.contains('.')) name = name.substring(0, name.indexOf('.'));
    String filename = _createUniqueFilename(configs.launchDir, name, 'yaml');

    LaunchConfiguration config = configs.createConfig(filename, content);

    atom.notifications.addInfo(
      'Created a ${type} launch configuration for `${primaryResource}`.',
      description: 'Created ${config._getRelativeConfigPath()}.'
    );

    _changeController.add(null);

    return config;
  }

  Stream get onChange => _changeController.stream;

  void dispose() {
    List<_ProjectConfigurations> configs = _projectConfigs.values.toList();
    _projectConfigs.clear();
    for (_ProjectConfigurations config in configs) {
      config.dispose();
    }
  }

  _ProjectConfigurations _getCreateProjectConfig(String path) {
    if (!_projectConfigs.containsKey(path)) {
      Directory launchDir = _getLaunchDir(path);
      _projectConfigs[path] = new _ProjectConfigurations(path, launchDir);
      _changeController.add(null);
    }
    return _projectConfigs[path];
  }

  void _handleProjectAdded(DartProject project) {
    _getCreateProjectConfig(project.path);
  }

  void _handleProjectRemoved(DartProject project) {
    _ProjectConfigurations config = _projectConfigs.remove(project.path);
    config?.dispose();
    _changeController.add(null);
  }

  void initFromStored(dynamic storedData) {
    if (storedData is Map) {
      _launchTimestamps = new Map.from(storedData);
    } else {
      _launchTimestamps = <String, int>{};
    }
  }

  dynamic toStorable() => _launchTimestamps;
}

String _createUniqueFilename(Directory dir, String name, String ext) {
  Set<String> names = new Set.from(dir.getEntriesSync().map((entry) => entry.path));
  String fullName = '${name}.${ext}';
  if (!names.contains(fullName)) return fullName;

  int i = 2;

  while (true) {
    fullName = '${name}_${i}.{ext}';
    if (!names.contains(fullName)) return fullName;
    i++;
  }
}

/// A configuration for a particular launch type.
class LaunchConfiguration {
  static Function get comparator {
    return (LaunchConfiguration a, LaunchConfiguration b) {
      return a.getDisplayName().compareTo(b.getDisplayName());
    };
  }

  final String projectPath;

  File _file;
  Map _map;

  LaunchConfiguration._parse(this.projectPath, File file, [String contents]) {
    this._file = file;
    reparse(contents);
  }

  String get launchFileName => fs.basename(_file.path);

  String get configYamlPath => _file.path;

  String get type => _map['type'];

  /// Return the 'path' field from the launch config file. This path is relative
  /// to the project path.
  String get shortResourceName => _map['path'];

  /// Similar to [shortResourceName] except this is an absolute path.
  String get primaryResource {
    return shortResourceName == null
      ? null
      : fs.join(projectPath, shortResourceName);
  }

  /// Return the type specific arguments for this launch configuration.
  Map<String, dynamic> get typeArgs {
    var data = _map[type];
    return data is Map ? new Map.from(data) : <String, dynamic>{};
  }

  String get cwd {
    if (typeArgs['cwd'] is String) {
      String str = typeArgs['cwd'].trim();
      if (str.isEmpty) return null;
      if (str.startsWith(fs.separator) || str.startsWith('/')) return str;
      if (isWindows && str.length >= 2 && str[1] == ':') return str;
      return fs.join(projectPath, str);
    } else {
      return null;
    }
  }

  bool get debug => (typeArgs['debug'] is bool) ? typeArgs['debug'] : true;

  bool get checked => (typeArgs['checked'] is bool) ? typeArgs['checked'] : true;

  String get argsAsString {
    var val = typeArgs['args'];
    if (val == null) return null;
    if (val is String) return val;

    if (val is List) {
      // Quote args with spaces.
      return val.map((val) {
        String str = '${val}';
        return str.contains(' ') ? '"${val}"' : val;
      }).join(' ');
    }

    return '${val}';
  }

  List<String> get argsAsList {
    var val = typeArgs['args'];
    if (val == null) return <String>[];
    if (val is List) return new List<String>.from(val);

    String str = '${val}';
    // TODO: Handle args wrapped by quotes.
    return str.split(' ');
  }

  String getDisplayName() => '${shortResourceName} (${type})';

  /// Update the timestamp for this launch configuration.
  void touch() {
    int time = new DateTime.now().millisecondsSinceEpoch;
    launchConfigurationManager._launchTimestamps[launchFileName] = time;
  }

  /// Get the last launch time.
  int get timestamp {
    var time = launchConfigurationManager._launchTimestamps[launchFileName];
    return time == null ? 0 : time;
  }

  String toString() {
    return '${launchFileName}: ${type}, ${shortResourceName}, ${type}: ${typeArgs}';
  }

  bool operator ==(other) {
    if (other is! LaunchConfiguration) return false;
    return primaryResource == other.primaryResource && type == other.type;
  }

  int get hashCode => primaryResource?.hashCode ?? 0;

  String _getRelativeConfigPath() {
    String path = _file.path;
    String parent = fs.dirname(projectPath);
    if (path.startsWith(parent)) {
      path = path.substring(parent.length);
      if (path.startsWith(fs.separator)) path = path.substring(1);
      return path;
    } else {
      return path;
    }
  }

  void reparse([String contents]) {
    if (contents != null || _file.existsSync()) {
      try {
        var parsed = loadYaml(contents == null ? _file.readSync(true) : contents);
        _map = parsed is Map ? parsed : {};
      } catch (e) {
        _map = {};
      }
    }
  }
}

Directory _getLaunchDir(String projectPath) {
  return new Directory.fromPath(fs.join(projectPath, '.atom', 'launches'));
}

class _ProjectConfigurations implements Disposable {
  final String projectPath;
  final Directory launchDir;

  List<LaunchConfiguration> _configs;
  StreamSubscription _sub;

  _ProjectConfigurations(this.projectPath, this.launchDir) {
    _listenToLaunchDir();
  }

  List<LaunchConfiguration> getConfigs() {
    if (_configs == null) {
      _reparse();
    } else {
      for (LaunchConfiguration config in _configs) {
        config.reparse();
      }
    }

    return _configs;
  }

  LaunchConfiguration createConfig(String filename, String contents) {
    _configs = null;

    File file = launchDir.getFile(filename);

    if (file.existsSync()) {
      file.writeSync(contents);
    } else {
      file.create().then((_) {
        file.writeSync(contents);
        _listenToLaunchDir();
      });
    }

    return new LaunchConfiguration._parse(projectPath, file, contents);
  }

  void _listenToLaunchDir() {
    if (_sub == null && launchDir.existsSync()) {
      _sub = launchDir.onDidChange.listen((_) => _configs = null);
    }
  }

  void _reparse() {
    _configs = [];

    if (launchDir.existsSync()) {
      for (Entry entry in launchDir.getEntriesSync()) {
        if (entry is! File || !entry.path.endsWith('.yaml')) continue;

        try {
          _configs.add(new LaunchConfiguration._parse(projectPath, entry));
        } catch (e) {
          _logger.info('Error parsing ${entry.path}', e);
        }
      }
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}
