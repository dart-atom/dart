library atom.sky.run_app;

import 'dart:async';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../jobs.dart';
import '../process.dart';
import '../projects.dart';
import '../state.dart';
import '../utils.dart';

final Logger _logger = new Logger('sky');

class SkyToolManager implements Disposable, ContextMenuContributor {
  Disposables disposables = new Disposables();

  SkyToolManager() {
    disposables.add(atom.commands.add(
        '.tree-view', 'dartlang:run-sky-application', (AtomEvent event) {
      new RunSkyAppJob(event.targetFilePath).schedule();
    }));
    disposables.add(atom.commands.add(
        'atom-text-editor', 'dartlang:run-sky-application', (AtomEvent event) {
      new RunSkyAppJob(event.editor.getPath()).schedule();
    }));
  }

  void dispose() => disposables.dispose();

  List<ContextMenuItem> getTreeViewContributions() {
    return [
      new RunSkyAppContextCommand(
          'Run Sky Application', 'dartlang:run-sky-application')
    ];
  }
}

class RunSkyAppJob extends Job {
  final String path;

  RunSkyAppJob(this.path) : super('Launching Sky application');

  bool get quiet => true;

  Future run() {
    DartProject project = projectManager.getProjectFor(path);
    String sky_tool = join(project.directory, 'packages', 'sky', 'sky_tool');
    ProcessRunner runner;

    if (isMac) {
      // On the mac, run under bash.
      runner = new ProcessRunner(
        '/bin/bash', args: ['-l', '-c', '${sky_tool} start'], cwd: project.path);
    } else {
      runner = new ProcessRunner(
        'python', args: [sky_tool, 'start'], cwd: project.path);
    }

    ProcessNotifier notifier = new ProcessNotifier(name);
    runner.execStreaming();
    return notifier.watch(runner);
  }
}

class RunSkyAppContextCommand extends ContextMenuItem {
  RunSkyAppContextCommand(String label, String command) : super(label, command);

  bool shouldDisplay(AtomEvent event) {
    String filePath = event.targetFilePath;
    DartProject project = projectManager.getProjectFor(filePath);
    if (project == null) return false;
    File skyTool = new File.fromPath(
        join(project.directory, 'packages', 'sky', 'sky_tool'));
    return skyTool.existsSync();
  }
}
