import 'package:atom/node/fs.dart';
import 'package:yaml/yaml.dart';

const _checkDartinoProject = 'checkDartinoProject';

class DartinoProjectSettings {
  final Directory projectDirectory;
  Map _settings;

  DartinoProjectSettings(this.projectDirectory);

  /// Return `true` if the user should be prompted when checking
  /// to see if a project is a well formed Dartino project.
  bool get checkDartinoProject {
    return this[_checkDartinoProject] != 'false';
  }

  void set checkDartinoProject(bool value) {
    this[_checkDartinoProject] = value ? 'true' : 'false';
  }

  String operator [](String key) {
    if (_settings == null) {
      try {
        var parsed = loadYaml(_settingsFile.readSync(true));
        _settings = parsed is Map ? parsed : {};
      } catch (e) {
        _settings = {};
      }
    }
    var value = _settings[key];
    return value is String ? value : null;
  }

  void operator []=(String key, String value) {
    if (this[key] == value) return;
    if (value != null) {
      _settings[key] = value;
    } else {
      _settings.remove(key);
    }
    var buf = new StringBuffer();
    buf.writeln('# Dartino settings');
    for (String key in _settings.keys.toList()..sort()) {
      buf.writeln('$key: ${_settings[key]}');
    }
    _settingsFile.create().then((_) {
      _settingsFile.writeSync(buf.toString());
    });
  }

  File get _settingsFile => new File.fromPath(
      fs.join(projectDirectory.path, '.atom', 'dartino', 'settings.yaml'));
}
