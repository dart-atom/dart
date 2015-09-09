library atom.sky.run_app;

import 'dart:async';

import 'package:logging/logging.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../jobs.dart';
import '../launch.dart';
import '../process.dart';
import '../projects.dart';
import '../state.dart';
import '../utils.dart';

final Logger _logger = new Logger('sky.run_app');

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

    if (project == null) return new Future.error("File not in a Dart project.");

    String sky_tool = join(project.directory, 'packages', 'sky', 'sky_tool');
    bool exists = new File.fromPath(sky_tool).existsSync();

    if (!exists) {
      return new Future.error("Unable to locate 'packages/sky/sky_tool'; did "
          "you import the 'sky' package into your project?");
    }

    ProcessRunner runner;

    if (isMac) {
      // On the mac, run under bash.
      runner = new ProcessRunner(
        '/bin/bash', args: ['-l', '-c', '${sky_tool} start'], cwd: project.path);
    } else {
      runner = new ProcessRunner(
        'python', args: [sky_tool, 'start'], cwd: project.path);
    }

    Launch launch = new Launch(
        new LaunchType(LaunchType.SKY),
        'lib/main.dart',
        launchManager,
        killHandler: () => runner.kill());
    launchManager.addLaunch(launch);

    runner.execStreaming();

    runner.onStdout.listen((str) => launch.pipeStdout(str));
    runner.onStderr.listen((str) => launch.pipeStderr(str));

    return runner.onExit.then((code) {
      launch.launchTerminated(code);
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
