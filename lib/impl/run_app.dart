library atom.run_app;

import 'dart:async';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../jobs.dart';
import '../launch.dart';
import '../projects.dart';
import '../state.dart';
import '../utils.dart';

final Logger _logger = new Logger('atom.run_app');

class RunApplicationManager implements Disposable, ContextMenuContributor {
  Disposables disposables = new Disposables();

  RunApplicationManager() {
    disposables.add(atom.commands.add(
        '.tree-view', 'dartlang:run-application', (AtomEvent event) {
      event.stopImmediatePropagation();
      new RunApplicationJob(event.targetFilePath).schedule();
    }));
    disposables.add(atom.commands.add(
        'atom-text-editor', 'dartlang:run-application', (AtomEvent event) {
      event.stopImmediatePropagation();
      event.preventDefault();
      new RunApplicationJob(event.editor.getPath()).schedule();
    }));
  }

  void dispose() => disposables.dispose();

  List<ContextMenuItem> getTreeViewContributions() {
    return [
      new RunAppContextCommand('Run Application', 'dartlang:run-application')
    ];
  }
}

class RunApplicationJob extends Job {
  final String path;

  RunApplicationJob(this.path) : super('Launching application');

  bool get quiet => true;

  Future run() async {
    // TODO: Look for already created launch configs for the path.

    LaunchType launchType = launchManager.getHandlerFor(path);

    if (launchType == null) {
      return new Future.error("Unable to locate a suitable handler to run '${path}'.");
    } else {
      LaunchConfiguration configuration = launchType.createConfiguration(path);
      return launchType.performLaunch(launchManager, configuration);
    }
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
