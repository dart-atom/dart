library atom.run;

import 'dart:async';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../projects.dart';
import '../state.dart';
import '../utils.dart';
import 'launch.dart';
import 'launch_configs.dart';

final Logger _logger = new Logger('atom.run');

// cmd-R, on exact match:
// -get existing launch config
// -create new one
// -launch it

// cmd-R, no exact match:
// -get existing project configs
// -launch last one
// -or, show a dialog to launch available project apps

/// Contribute the Run commands.
class RunApplicationManager implements Disposable, ContextMenuContributor {
  Disposables disposables = new Disposables();

  RunApplicationManager() {
    var stop = (AtomEvent event) {
      event.stopImmediatePropagation();
      event.preventDefault();
    };

    disposables.add(
        atom.commands.add('.tree-view', 'dartlang:run-application', (event) {
      stop(event);
      _handleRunCommand(event.targetFilePath);
    }));
    disposables.add(
        atom.commands.add('atom-text-editor', 'dartlang:run-application', (event) {
      stop(event);
      _handleRunCommand(event.editor.getPath());
    }));
  }

  void dispose() => disposables.dispose();

  List<ContextMenuItem> getTreeViewContributions() {
    return [
      new _RunAppContextCommand('Run Application', 'dartlang:run-application')
    ];
  }

  void _handleRunCommand(String path) {
    if (path == null) return;

    _preRunConfigSearch();

    String projectPath = _getProjectPath(path);
    LaunchConfiguration config = _getConfigFor(projectPath, path);

    // Look for already created launch configs for the path.
    if (config != null) {
      _logger.fine("Using existing launch config for '${path}'.");
      run(config);
      return;
    }

    LaunchType launchType = launchManager.getHandlerFor(path);

    if (launchType != null) {
      LaunchConfiguration config = _createConfig(projectPath, launchType, path);
      _logger.fine("Creating new launch config for '${path}'.");
      run(config);
      return;
    }

    DartProject project = projectManager.getProjectFor(path);

    if (project != null) {
      // Look for the last launched config for the project; run it.
      config = _newest(launchConfigurationManager.getConfigsFor(project.path));

      if (config != null) {
        _logger.fine("Using recent launch config '${config}'.");
        run(config);
        return;
      }
    }

    // Gather all potential runnables for this project.
    List<Launchable> runnables = launchManager.getAllLaunchables(project);

    if (runnables.isEmpty) {
      String displayPath = project == null ? path : project.getRelative(path);
      atom.notifications.addWarning(
          'Unable to locate a suitable execution handler for file ${displayPath}.');
    } else if (runnables.length == 1) {
      Launchable launchable = runnables.first;
      config = launchConfigurationManager.createNewConfig(
        projectPath,
        launchable.type.type,
        launchable.relativePath,
        launchable.type.getDefaultConfigText()
      );

      _logger.fine("Found one runnable in project: '${config}'.");
      run(config);
    } else {
      atom.notifications.addWarning(
        'This project contains more than one potentially runnable file; '
        'please select a specific file.');
    }
  }

  String _getProjectPath(String path) {
    DartProject project = projectManager.getProjectFor(path);
    if (project != null) return project.path;
    return atom.project.relativizePath(path)[0];
  }

  void _preRunConfigSearch() {
    // Save all dirty editors.
    atom.workspace.saveAll();
  }

  void _preLaunch() {

  }

  void run(LaunchConfiguration config) {
    _preLaunch();

    _logger.info("Launching '${config}'.");
    LaunchType launchType = launchManager.getLaunchType(config.type);

    if (launchType == null) {
      atom.notifications.addError(
        "No handler for launch type '${config.type}' found.");
    } else {
      config.touch();

      launchType.performLaunch(launchManager, config).catchError((e) {
        atom.notifications.addError(
            "Error running '${config.primaryResource}'.",
            detail: '${e}');
      });
    }
  }

  LaunchConfiguration _getConfigFor(String projectPath, String path) {
    List<LaunchConfiguration> configs =
        launchConfigurationManager.getConfigsFor(projectPath);

    // Check if the file _is_ a launch config.
    for (LaunchConfiguration config in configs) {
      if (config.configYamlPath == path) return config;
    }

    return _newest(configs.where((config) => config.primaryResource == path));
  }

  LaunchConfiguration _createConfig(String projectPath, LaunchType launchType, String path) {
    String relativePath = path;

    if (relativePath.startsWith(projectPath)) {
      relativePath = relativePath.substring(projectPath.length);
      if (relativePath.startsWith(separator)) relativePath = relativePath.substring(1);
    }

    return launchConfigurationManager.createNewConfig(
      projectPath,
      launchType.type,
      relativePath,
      launchType.getDefaultConfigText()
    );
  }

  LaunchConfiguration _newest(Iterable<LaunchConfiguration> configs) {
    if (configs.isEmpty) return null;

    LaunchConfiguration config = configs.first;

    for (LaunchConfiguration c in configs) {
      if (c.timestamp > config.timestamp) config = c;
    }

    return config;
  }
}

// TODO: store the current selection per project

/// Manage the list of available launches for the currently selected project,
/// and the currently selected launch (what would be run when the user hits
/// cmd-R).
///
/// The list of launches contains launch configurations that the user has
/// already un, as well as potential launch configs for things which are
/// runnable but have not yet been run.
class ProjectLaunchManager implements Disposable {
  Disposable disposeable;
  StreamSubscriptions subs = new StreamSubscriptions();

  RunnableConfig _selectedRunnable;
  List<RunnableConfig> _runnables = [];
  String _currentFile;

  StreamController<RunnableConfig> _selectedRunnableController = new StreamController.broadcast();
  StreamController<List<RunnableConfig>> _runnablesController = new StreamController.broadcast();

  ProjectLaunchManager() {
    disposeable = atom.workspace.observeActivePaneItem(_updateFromActiveEditor);
    subs.add(projectManager.onProjectsChanged.listen(_updateFromActiveEditor));
    _updateFromActiveEditor();
  }

  String get currentFile => _currentFile;

  DartProject get currentProject => projectManager.getProjectFor(_currentFile);

  RunnableConfig get selectedRunnable => _selectedRunnable;

  List<RunnableConfig> get runnables => _runnables;

  Stream<RunnableConfig> get onSelectedRunnableChanged => _selectedRunnableController.stream;
  Stream<List<RunnableConfig>> get onRunnablesChanged => _runnablesController.stream;

  void setSelectedRunnable(RunnableConfig runnable) {
    _selectedRunnable = runnable;
    _selectedRunnableController.add(selectedRunnable);
  }

  void _updateFromActiveEditor([_]) {
    TextEditor editor = atom.workspace.getActiveTextEditor();
    _currentFile = editor?.getPath();

    if (currentProject == null) {
      _selectedRunnable = null;
      _runnables.clear();

      _selectedRunnableController.add(selectedRunnable);
      _runnablesController.add(runnables);
    } else {
      String projectPath = currentProject.path;

      List<LaunchConfiguration> configs = launchConfigurationManager.getConfigsFor(projectPath);
      List<Launchable> launchables = launchManager.getAllLaunchables(currentProject);

      for (LaunchConfiguration config in configs) {
        Launchable tempLaunchable = new Launchable(
          launchManager.getLaunchType(config.type),
          config.shortResourceName
        );
        launchables.remove(tempLaunchable);
      }

      _runnables.clear();

      _runnables.addAll(configs.map((LaunchConfiguration config) {
        return new RunnableConfig.fromLaunchConfig(projectPath, config);
      }));
      _runnables.addAll(launchables.map((Launchable launchable) {
        return new RunnableConfig.fromLaunchable(projectPath, launchable);
      }));

      _runnablesController.add(runnables);

      if (_selectedRunnable != null) {
        if (!_runnables.contains(_selectedRunnable)) {
          _selectedRunnable = _runnables.isNotEmpty ? _runnables.first : null;
          _selectedRunnableController.add(_selectedRunnable);
        }
      }
    }
  }

  void dispose() {
    disposeable.dispose();
    subs.cancel();
  }
}

/// Something that's runnable. This is either a [Launchable] - something
/// potentially runnable that the user has never run - or a
/// [LaunchConfiguration] - something the user has already run at least once.
class RunnableConfig implements Comparable<RunnableConfig> {
  final String projectPath;

  Launchable _launchable;
  LaunchConfiguration _config;

  RunnableConfig.fromLaunchable(this.projectPath, this._launchable);
  RunnableConfig.fromLaunchConfig(this.projectPath, this._config);

  bool get hasConfig => _config != null;

  String getDisplayName() {
    if (_config != null) {
      return '${_config.shortResourceName} • ${_config.type}';
    } else {
      return '${_launchable.relativePath} (${_launchable.type})';
    }
  }

  /// This will create a launch configuration if one does not already exist.
  LaunchConfiguration getCreateLaunchConfig() {
    if (_config == null) {
      _config = launchConfigurationManager.createNewConfig(
        projectPath,
        _launchable.type.type,
        _launchable.relativePath,
        _launchable.type.getDefaultConfigText()
      );
    }

    return _config;
  }

  int compareTo(RunnableConfig other) {
    if (hasConfig && !other.hasConfig) return -1;
    if (!hasConfig && other.hasConfig) return 1;
    return getDisplayName().toLowerCase().compareTo(other.getDisplayName().toLowerCase());
  }

  bool operator ==(other) {
    if (other is! RunnableConfig) return false;

    if (hasConfig) {
      if (!other.hasConfig) return false;
      return _config == other._config;
    } else {
      if (other.hasConfig) return false;
      return _launchable == other._launchable;
    }
  }

  int get hashCode => getDisplayName().hashCode;
}

class _RunAppContextCommand extends ContextMenuItem {
  _RunAppContextCommand(String label, String command) : super(label, command);

  bool shouldDisplay(AtomEvent event) {
    String filePath = event.targetFilePath;
    DartProject project = projectManager.getProjectFor(filePath);
    if (project == null) return false;
    return launchManager.getHandlerFor(filePath) != null;
  }
}
