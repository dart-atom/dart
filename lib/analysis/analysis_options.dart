library atom.analysis_options;

import 'package:yaml/yaml.dart' as yaml;

// .analysis_options
// analyzer:
//   exclude:
//     - build/**

class AnalysisOptions {
  static const String defaultFileName = '.analysis_options';

  yaml.YamlDocument _document;
  bool _dirty = false;

  AnalysisOptions([String data]) {
    _document = yaml.loadYamlDocument(data == null ? 'analyzer: []' : data);
    if (_document.contents is! Map) {
      _document = yaml.loadYamlDocument('analyzer: []');
    }
  }

  /// Return the entire `exclude` section.
  List<String> getIgnoredRules() {
    var analyzer = (_document.contents as Map)['analyzer'];
    if (analyzer is! Map) return [];
    var exclude = analyzer['exclude'];
    return exclude is List ? exclude : [];
  }

  /// Return the list of exclutions that end in `/**`, with the suffix removed.
  List<String> getIgnoredDirectories() {
    return getIgnoredRules()
        .where((str) => str.endsWith('/**'))
        .map((str) => str.substring(0, str.length - 3))
        .toList();
  }

  void addIgnoredDirectory(String path) {
    path = '${path}/**';
    _getMutableExcludeList().add(path);
    _dirty = true;
  }

  void removeIgnoredDirectory(String path) {
    path = '${path}/**';
    _getMutableExcludeList().remove(path);
    _dirty = true;
  }

  bool get dirty => _dirty;
  set dirty(bool value) {
    _dirty = value;
  }

  List<String> _getMutableExcludeList() {
    var analyzer = (_document.contents as Map)['analyzer'];
    if (analyzer is! Map) {
      analyzer = {};
      (_document.contents as Map)['analyzer'] = analyzer;
    }

    var exclude = analyzer['exclude'];
    if (exclude is! List) {
      exclude = [];
      analyzer['exclude'] = exclude;
    }

    return exclude;
  }

  String writeYaml() => _document.toString();
}
