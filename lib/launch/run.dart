library atom.run;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../projects.dart';
import '../state.dart';
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

WorkspaceLaunchManager get _workspaceLaunchManager => deps[WorkspaceLaunchManager];

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
      _handleTreeViewRunCommand(event.targetFilePath);
    }));
    disposables.add(
        atom.commands.add('.tree-view', 'dartlang:app-full-restart', (event) {
      stop(event);
      _handleTreeViewFullRestartCommand(event.targetFilePath);
    }));
    disposables.add(
        atom.commands.add('atom-text-editor', 'dartlang:run-application', (event) {
      stop(event);
      TextEditor editor = event.editor;
      _handleEditorRunCommand(editor.getPath(), editor.getText());
    }));
    disposables.add(
        atom.commands.add('atom-text-editor', 'dartlang:app-full-restart', (event) {
      stop(event);
      TextEditor editor = event.editor;
      _handleEditorFullRestartCommand(editor.getPath(), editor.getText());
    }));
  }

  void dispose() => disposables.dispose();

  List<ContextMenuItem> getTreeViewContributions() {
    return [
      new _RunAppContextCommand('Run Application', 'dartlang:run-application')
    ];
  }

  void _handleTreeViewRunCommand(String path) {
    File file = new File.fromPath(path);
    _handleRunCommand(path, new LaunchData(file.readSync()), explicitFile: true);
  }

  void _handleEditorRunCommand(String path, String contents) {
    _handleRunCommand(path, new LaunchData(contents));
  }

  void _handleTreeViewFullRestartCommand(String path) {
    File file = new File.fromPath(path);
    _handleFullRestartCommand(path, new LaunchData(file.readSync()));
  }

  void _handleEditorFullRestartCommand(String path, String contents) {
    _handleFullRestartCommand(path, new LaunchData(contents));
  }

  void _handleRunCommand(String path, LaunchData data, { bool explicitFile: false }) {
    if (path == null) return;

    _preRunConfigSearch();

    DartProject project = projectManager.getProjectFor(path);
    WorkspaceLaunchManager workspaceLaunchManager = _workspaceLaunchManager;
    RunnableConfig runnable = workspaceLaunchManager.selectedRunnable;

    if (explicitFile) {
      // If the current select == the current file, use that.
      if (runnable != null && runnable.path == path) {
        run(runnable.getCreateLaunchConfig());
      } else {
        // If the file has a launch config, use that.
        DartProject project = projectManager.getProjectFor(path);
        List<LaunchConfiguration> configs = project == null ?
           [] : launchConfigurationManager.getConfigsForProject(project.path);

        configs = configs.where((LaunchConfiguration c) => path == c.primaryResource).toList();

        if (configs.isNotEmpty) {
          LaunchConfiguration config = configs.first;
          for (LaunchConfiguration c in configs) {
            if (c.timestamp > config.timestamp) config = c;
          }
          run(config);
        } else {
          // If the file is runnable, use that.
          List<Launchable> launchables = launchManager.getAllLaunchables(path, data);

          if (launchables.isNotEmpty) {
            Launchable launchable = launchables.first;
            LaunchConfiguration config = launchConfigurationManager.createNewConfig(
              launchable.projectPath,
              launchable.type.type,
              launchable.relativePath,
              launchable.type.getDefaultConfigText()
            );
            run(config);
          } else {
            String displayPath = project == null ? path : project.getRelative(path);
            atom.notifications.addWarning(
                'Unable to locate a suitable execution handler for file ${displayPath}.');
          }
        }
      }
    } else {
      if (runnable != null) {
        run(runnable.getCreateLaunchConfig());
      } else {
        String displayPath = project == null ? path : project.getRelative(path);
        atom.notifications.addWarning(
            'Unable to locate a suitable execution handler for file ${displayPath}.');
      }
    }
  }

  void _handleFullRestartCommand(String path, LaunchData data) {
    // determine the active launch
    Launch launch = launchManager.activeLaunch;

    // complain if there is none
    if (launch == null) {
      atom.notifications.addError('No application running to restart.');
      return;
    }

    // complain if it doesn't support restart
    if (!launch.supportsRestart) {
      atom.notifications.addError('The currently running application does not support restart.');
      return;
    }

    // ask it to do a full restart
    launch.restart(fullRestart: true).catchError((e) {
      atom.notifications.addWarning(e.toString());
    });
  }

  void _preRunConfigSearch() {
    // Save all dirty editors.
    atom.workspace.saveAll();
  }

  void _preLaunch() {
    // Save all dirty editors.
    atom.workspace.saveAll();
  }

  void run(LaunchConfiguration config) {
    _preLaunch();

    // Make sure we're running with the latest config file info.
    config.reparse();

    _logger.info("Launching '${config}'.");
    LaunchType launchType = launchManager.getLaunchType(config.type);

    if (launchType == null) {
      atom.notifications.addError(
        "No handler for launch type '${config.type}' found.");
    } else {
      config.touch();

      launchType.performLaunch(launchManager, config).catchError((e) {
        atom.notifications.addError(
          "Error running '${config.shortResourceName}'.",
          description: '${e}',
          dismissable: true
        );
      });
    }
  }
}

// TODO: Use this when calculating the best current launch selection.
// LaunchConfiguration _newest(Iterable<LaunchConfiguration> configs) {
//   if (configs.isEmpty) return null;
//
//   LaunchConfiguration config = configs.first;
//
//   for (LaunchConfiguration c in configs) {
//     if (c.timestamp > config.timestamp) config = c;
//   }
//
//   return config;
// }

/// Manage the list of available launches for the workspace, and the currently
/// selected launch (what would be run when the user hits cmd-R).
///
/// The list of launches contains launch configurations that the user has
/// already run, as well as potential launch configs for things which are
/// runnable but have not yet been run.
class WorkspaceLaunchManager implements Disposable {
  Disposable disposeable;
  StreamSubscriptions subs = new StreamSubscriptions();

  RunnableConfig _selectedRunnable;
  List<RunnableConfig> _runnables = [];
  String _currentFile;

  StreamController<RunnableConfig> _selectedRunnableController = new StreamController.broadcast();
  StreamController<List<RunnableConfig>> _runnablesController = new StreamController.broadcast();

  WorkspaceLaunchManager() {
    disposeable = atom.workspace.observeActivePaneItem((dynamic item) {
      _updateFromActiveEditor();
    });
    subs.add(projectManager.onProjectsChanged.listen((List<DartProject> projects) {
      _updateFromActiveEditor();
    }));
    subs.add(launchConfigurationManager.onChange.listen((_) {
      _updateFromActiveEditor();
    }));
    _updateFromActiveEditor();
  }

  String get currentFile => _currentFile;

  RunnableConfig get selectedRunnable => _selectedRunnable;

  List<RunnableConfig> get runnables => _runnables;

  Stream<RunnableConfig> get onSelectedRunnableChanged => _selectedRunnableController.stream;
  Stream<List<RunnableConfig>> get onRunnablesChanged => _runnablesController.stream;

  void setSelectedRunnable(RunnableConfig runnable) {
    _selectedRunnable = runnable;
    _selectedRunnableController.add(selectedRunnable);
  }

  void _updateFromActiveEditor() {
    TextEditor editor = atom.workspace.getActiveTextEditor();
    _currentFile = editor?.getPath();

    List<LaunchConfiguration> configs = launchConfigurationManager.getAllConfigs();
    List<Launchable> launchables = [];

    // Find launchables from the current active editor.
    if (_currentFile != null) {
      launchables = launchManager.getAllLaunchables(_currentFile, new LaunchData(editor.getText()));
    }

    for (LaunchConfiguration config in configs) {
      Launchable tempLaunchable = new Launchable(
        launchManager.getLaunchType(config.type),
        config.projectPath,
        config.shortResourceName
      );
      launchables.remove(tempLaunchable);
    }

    _runnables.clear();

    _runnables.addAll(configs.map((LaunchConfiguration config) {
      return new RunnableConfig.fromLaunchConfig(config);
    }));
    _runnables.addAll(launchables.map((Launchable launchable) {
      return new RunnableConfig.fromLaunchable(launchable);
    }));
    _runnables.sort();

    _runnablesController.add(runnables);

    // TODO: We should prefer to have a runnable that matches the current file
    // here, if one exists. We should also try and make the user's selection as
    // stable and sticky as possible.

    if (_selectedRunnable != null && !_runnables.contains(_selectedRunnable)) {
      _selectedRunnable = _runnables.isNotEmpty ? _runnables.first : null;
      _selectedRunnableController.add(_selectedRunnable);
    } else if (_selectedRunnable == null && _runnables.isNotEmpty) {
      _selectedRunnable = _runnables.first;
      _selectedRunnableController.add(_selectedRunnable);
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
  Launchable _launchable;
  LaunchConfiguration _config;

  RunnableConfig.fromLaunchable(this._launchable);
  RunnableConfig.fromLaunchConfig(this._config);

  bool get hasConfig => _config != null;

  String get projectPath {
    if (_config != null) {
      return _config.projectPath;
    } else {
      return _launchable.projectPath;
    }
  }

  String get path => _config  != null ? _config.primaryResource : _launchable.path;

  String getDisplayName() {
    if (_config != null) {
      String projectName = fs.basename(_config.projectPath);
      return '${projectName}: ${_config.shortResourceName} (${_config.type})';
    } else {
      String projectName = fs.basename(_launchable.projectPath);
      return '${projectName}: ${_launchable.relativePath} (${_launchable.type}) •';
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

  bool get isFlutterRunnable => type == 'flutter';

  String get type => _config != null ? _config.type : _launchable.type;

  int compareTo(RunnableConfig other) {
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

  String toString() => getDisplayName();
}

class _RunAppContextCommand extends ContextMenuItem {
  _RunAppContextCommand(String label, String command) : super(label, command);

  bool shouldDisplay(AtomEvent event) {
    String filePath = event.targetFilePath;
    DartProject project = projectManager.getProjectFor(filePath);
    if (project == null) return false;
    if (!fs.statSync(filePath).isFile()) return false;
    File file = new File.fromPath(filePath);
    String contents = file.readSync();
    return launchManager.getHandlerFor(filePath, new LaunchData(contents)) != null;
  }
}
