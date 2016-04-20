library atom.analysis_options;

import 'package:atom/node/command.dart';
import 'package:atom/utils/disposable.dart';
import 'package:yaml/yaml.dart' as yaml;

// import '../atom_utils.dart' as atom_utils show separator;
// import '../projects.dart';

// .analysis_options
// analyzer:
//   exclude:
//     - build/**

const String analysisOptionsFileName = '.analysis_options';

class AnalysisOptionsManager implements Disposable, ContextMenuContributor {
  Disposables disposables = new Disposables();

  AnalysisOptionsManager() {
    // Disable these commands.
    // disposables.add(atom.commands.add('.tree-view', 'dartlang:analysis-exclude',
    //     (AtomEvent event) {
    //   _handleExclude(event.targetFilePath);
    // }));
    // disposables.add(atom.commands.add('.tree-view', 'dartlang:analysis-include',
    //     (AtomEvent event) {
    //   _handleInclude(event.targetFilePath);
    // }));
  }

  List<ContextMenuItem> getTreeViewContributions() {
    return [
      // TODO: Enable when we have a mutable yaml structure.
      // new _AnalysisContextCommand.exclude(
      //     'Exclude from Analysis', 'dartlang:analysis-exclude'),
      // new _AnalysisContextCommand.include(
      //     'Include in Analysis', 'dartlang:analysis-include')
    ];
  }

  // void _handleExclude(String path) {
  //   DartProject project = projectManager.getProjectFor(path);
  //   if (project == null) return;
  //   path = _relativePath(project, path);
  //   if (path.isEmpty) return;
  //
  //   atom.notifications.addSuccess('Excluded ${path} from analysis.');
  //   project.excludeDirectory(path);
  //
  //   if (analysisServer.isActive) {
  //     String projectPath = project.directory.path;
  //     analysisServer.server.analysis.reanalyze(roots: [projectPath]);
  //     atom.notifications.addInfo('Re-analyzing ${projectPath}.');
  //   }
  // }
  //
  // void _handleInclude(String path) {
  //   DartProject project = projectManager.getProjectFor(path);
  //   if (project == null) return;
  //   path = _relativePath(project, path);
  //   if (path.isEmpty) return;
  //
  //   atom.notifications.addInfo('Included ${path} in analysis.');
  //   project.includeDirectory(path);
  //
  //   if (analysisServer.isActive) {
  //     String projectPath = project.directory.path;
  //     analysisServer.server.analysis.reanalyze(roots: [projectPath]);
  //     atom.notifications.addInfo('Re-analyzing ${projectPath}.');
  //   }
  // }

  void dispose() => disposables.dispose();
}

// TODO: mutable yaml stuff

class AnalysisOptions {
  yaml.YamlDocument _document;
  bool _dirty = false;

  AnalysisOptions([String data]) {
    _document = yaml.loadYamlDocument(data == null ? 'analyzer: []' : data);

    // if (_document.contents is! Map) {
    //   _document = yaml.loadYamlDocument('analyzer: []');
    // }
    //
    // var analyzer = (_document.contents as Map)['analyzer'];
    // if (analyzer is! Map) {
    //   analyzer = {};
    //   (_document.contents as Map)['analyzer'] = analyzer;
    // }
    //
    // var exclude = analyzer['exclude'];
    // if (exclude is! List) {
    //   exclude = [];
    //   analyzer['exclude'] = exclude;
    // }
    //
    // analyzer['exclude'] = new List.from(analyzer['exclude']);
  }

  /// Return the entire `exclude` section.
  List<String> getIgnoredRules() {
    var analyzer = (_document.contents as Map)['analyzer'];
    if (analyzer is! Map) return [];
    dynamic exclude = analyzer['exclude'];
    return exclude is List<String> ? exclude : <String>[];
  }

  /// Return the list of exclutions that end in `/**`, with the suffix removed.
  List<String> getIgnoredDirectories() {
    return new List.from(getIgnoredRules()
        .where((str) => str.endsWith('/**') || str.endsWith(r'\**'))
        .map((str) => str.substring(0, str.length - 3)));
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
    // TODO: We need to have a mutable yaml structure.
    return [];
    //return (_document.contents as Map)['analyzer']['exclude'];
  }

  String writeYaml() => _document.toString();
}

// class _AnalysisContextCommand extends ContextMenuItem {
//   final bool _exclude;
//
//   _AnalysisContextCommand.exclude(String label, String command) :
//       _exclude = true, super(label, command);
//   _AnalysisContextCommand.include(String label, String command) :
//       _exclude = false, super(label, command);
//
//   bool shouldDisplay(AtomEvent event) {
//     String path = event.targetFilePath;
//     DartProject project = projectManager.getProjectFor(path);
//     if (project == null) return false;
//     Stats stats = statSync(path);
//     if (!stats.isDirectory()) return false;
//
//     path = _relativePath(project, path);
//     if (path.isEmpty) return false;
//
//     if (project.isDirectoryExplicitlyExcluded(path)) {
//       return _exclude == false;
//     } else {
//       return _exclude == true;
//     }
//   }
// }

// String _relativePath(DartProject project, String path) {
//   String projectPath = project.directory.path;
//   if (path.startsWith(projectPath)) {
//     path = path.substring(projectPath.length);
//     if (path.startsWith(atom_utils.separator)) path = path.substring(1);
//   }
//   return path;
// }
