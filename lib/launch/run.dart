library atom.run;

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
      new RunAppContextCommand('Run Application', 'dartlang:run-application')
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
      _run(config);
      return;
    }

    LaunchType launchType = launchManager.getHandlerFor(path);

    if (launchType != null) {
      LaunchConfiguration config = _createConfig(projectPath, launchType, path);
      _logger.fine("Creating new launch config for '${path}'.");
      _run(config);
      return;
    }

    DartProject project = projectManager.getProjectFor(path);

    if (project != null) {
      // Look for the last launched config for the project; run it.
      config = _newest(launchConfigurationManager.getConfigsFor(project.path));

      if (config != null) {
        _logger.fine("Using recent launch config '${config}'.");
        _run(config);
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
      _run(config);
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

  void _run(LaunchConfiguration config) {
    _preLaunch();

    _logger.info("Launching '${config}'.");
    config.touch();

    LaunchType launchType = launchManager.getLaunchType(config.type);
    launchType.performLaunch(launchManager, config).catchError((e) {
      atom.notifications.addError(
          "Error running '${config.primaryResource}'.",
          detail: '${e}');
    });
  }

  LaunchConfiguration _getConfigFor(String projectPath, String path) {
    List<LaunchConfiguration> configs =
        launchConfigurationManager.getConfigsFor(projectPath);
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

class RunAppContextCommand extends ContextMenuItem {
  RunAppContextCommand(String label, String command) : super(label, command);

  bool shouldDisplay(AtomEvent event) {
    String filePath = event.targetFilePath;
    DartProject project = projectManager.getProjectFor(filePath);
    if (project == null) return false;
    return launchManager.getHandlerFor(filePath) != null;
  }
}
