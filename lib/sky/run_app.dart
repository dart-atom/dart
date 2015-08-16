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
    disposables.add(atom.commands
        .add('.tree-view', 'dartlang:run-sky-application', (AtomEvent event) {
      new RunSkyAppJob(event.targetFilePath).schedule();
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

  bool get pinResult => true;

  Future run() {
    DartProject project = projectManager.getProjectFor(path);
    String sky_tool = join(project.directory, 'packages', 'sky', 'sky_tool');
    ProcessRunner runner;
    if (isMac) {
      // On the mac, run under bash.
      runner = new ProcessRunner('/bin/bash',
          args: ['-l', '-c', sky_tool], cwd: project.path);
    } else {
      runner = new ProcessRunner('python',
          args: [sky_tool, 'start'], cwd: project.path);
    }
    return runner.execSimple().then((ProcessResult result) {
      if (result.exit != 0) throw '${result.stdout}\n${result.stderr}';
      return result.stdout;
    });
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
