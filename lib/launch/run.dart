library atom.run;

import 'package:logging/logging.dart';

import '../atom.dart';
import '../projects.dart';
import '../state.dart';
import '../utils.dart';
import 'launch.dart';

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

    disposables.add(atom.commands.add(
        '.tree-view', 'dartlang:run-application', (event) {
      stop(event);
      _handleFastRunCommand(event.targetFilePath);
    }));
    disposables.add(atom.commands.add(
        'atom-text-editor', 'dartlang:run-application', (event) {
      stop(event);
      _handleFastRunCommand(event.editor.getPath());
    }));
    disposables.add(atom.commands.add(
        '.tree-view', 'dartlang:run-application-configuration', (event) {
      stop(event);
      _handleRunConfigCommand(event.targetFilePath);
    }));
    disposables.add(atom.commands.add(
        'atom-text-editor', 'dartlang:run-application-configuration', (event) {
      stop(event);
      _handleRunConfigCommand(event.editor.getPath());
    }));
  }

  void dispose() => disposables.dispose();

  List<ContextMenuItem> getTreeViewContributions() {
    return [
      new RunAppContextCommand('Run Application', 'dartlang:run-application'),
      new RunAppContextCommand('Run App Configuration…', 'dartlang:run-application-configuration')
    ];
  }

  void _handleFastRunCommand(String path) {
    LaunchConfiguration config = _getConfigFor(path);

    // Look for already created launch configs for the path.
    if (config != null) {
      _logger.fine("Using existing launch config for '${path}'.");
      _run(config);
      return;
    }

    LaunchType launchType = launchManager.getHandlerFor(path);

    if (launchType != null) {
      LaunchConfiguration config = _createConfig(launchType, path);
      _logger.fine("Creating new launch config for '${path}'.");
      _run(config);
      return;
    }

    DartProject project = projectManager.getProjectFor(path);

    if (project != null) {
      // Look for the last launched config for the project; run it.
      config = _newest(launchManager.getConfigurationsForProject(project));

      if (config != null) {
        _logger.fine("Using recent launch config '${config}'.");
        _run(config);
        return;
      }
    }

    String displayPath = project == null ? path : project.getRelative(path);
    atom.notifications.addWarning(
        'Unable to locate a suitable execution handler for file ${displayPath}.');

    // TODO: Else, open the config editing dialog?

  }

  void _preLaunch() {
    // Save all dirty editors.
    atom.workspace.saveAll();
  }

  void _run(LaunchConfiguration config) {
    _preLaunch();

    _logger.info("Launching '${config}'.");
    config.touch();

    LaunchType launchType = launchManager.getLaunchType(config.launchType);
    launchType.performLaunch(launchManager, config).catchError((e) {
      atom.notifications.addError(
          "Error running '${config.primaryResource}'.",
          detail: '${e}');
    });
  }

  void _handleRunConfigCommand(String path) {
    // TODO: Show an inline config editor.

    _handleFastRunCommand(path);
  }

  LaunchConfiguration _getConfigFor(String path) {
    return _newest(launchManager.getConfigurationsForPath(path));
  }

  LaunchConfiguration _createConfig(LaunchType launchType, String path) {
    LaunchConfiguration config = launchType.createConfiguration(path);
    launchManager.createConfiguration(config);
    return config;
  }

  LaunchConfiguration _newest(List<LaunchConfiguration> configs) {
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
