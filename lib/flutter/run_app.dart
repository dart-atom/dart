library atom.flutter.run_app;

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

final Logger _logger = new Logger('flutter.run_app');

/// The last Flutter app run.
String _lastRunProject;

class FlutterToolManager implements Disposable, ContextMenuContributor {
  Disposables disposables = new Disposables();

  FlutterToolManager() {
    disposables.add(atom.commands.add(
        '.tree-view', 'dartlang:run-flutter-application', (AtomEvent event) {
      event.stopImmediatePropagation();
      new RunFlutterAppJob(event.targetFilePath).schedule();
    }));
    disposables.add(atom.commands.add(
        'atom-text-editor', 'dartlang:run-flutter-application', (AtomEvent event) {
      event.stopImmediatePropagation();
      new RunFlutterAppJob(event.editor.getPath()).schedule();
    }));
  }

  void dispose() => disposables.dispose();

  List<ContextMenuItem> getTreeViewContributions() {
    return [
      new RunFlutterAppContextCommand(
          'Run Flutter Application', 'dartlang:run-flutter-application')
    ];
  }
}

class RunFlutterAppJob extends Job {
  final String path;

  ProcessRunner _runner;

  RunFlutterAppJob(this.path) : super('Launching Flutter application');

  bool get quiet => true;

  Future run() async {
    DartProject project = projectManager.getProjectFor(path);

    if (project == null) return new Future.error("File not in a Dart project.");

    String sky_tool = join(project.directory, 'packages', 'sky', 'sky_tool');
    bool exists = new File.fromPath(sky_tool).existsSync();

    if (!exists) {
      return new Future.error("Unable to locate 'packages/sky/sky_tool'; did "
          "you import the 'sky' package into your project?");
    }

    // If this is the first time we've launched an app this session, ensure
    // that the sky server isn't already running (and potentially serving an
    // older) app. Also, if we're launching a different application.
    if (_lastRunProject != project.path) {
      _lastRunProject = project.path;
      await _skyToolStop(project);
    }

    // Chain together both 'sky_tool start' and 'sky_tool logs'.
    _runner = _skyTool(project, ['start']);

    Launch launch = new Launch(
        new LaunchType(LaunchType.FLUTTER),
        'lib/main.dart',
        launchManager,
        killHandler: () => _runner.kill());
    launch.servicePort = 8181;
    launchManager.addLaunch(launch);

    _runner.execStreaming();

    _runner.onStdout.listen((str) => launch.pipeStdout(str));
    _runner.onStderr.listen((str) => launch.pipeStderr(str));

    launch.pipeStdout('[${_runner.cwd}] ${_runner.getDescription()}\n');

    return _runner.onExit.then((code) {
      _runner = null;

      if (code == 0) {
        // Chain 'sky_tool logs'.
        _runner = _skyTool(project, ['logs', '--clear']);
        _runner.execStreaming();
        _runner.onStdout.listen((str) => launch.pipeStdout(str));
        _runner.onStderr.listen((str) => launch.pipeStderr(str));

        // Don't return the future here.
        _runner.onExit.then((code) => launch.launchTerminated(code));
      } else {
        launch.launchTerminated(code);
      }
    });
  }

  ProcessRunner _skyTool(DartProject project, List<String> args) {
    final String skyToolPath = 'packages${separator}sky${separator}sky_tool';

    if (isMac) {
      // On the mac, run under bash.
      return new ProcessRunner('/bin/bash',
          args: ['-l', '-c', '${skyToolPath} ${args.join(' ')}'], cwd: project.path);
    } else {
      args.insert(0, skyToolPath);
      return new ProcessRunner('python', args: args, cwd: project.path);
    }
  }

  /// Run `sky_tool stop` and ignore any error conditions that may occur.
  Future _skyToolStop(DartProject project) {
    return _skyTool(project, ['stop']).execSimple();
  }
}

class RunFlutterAppContextCommand extends ContextMenuItem {
  RunFlutterAppContextCommand(String label, String command) : super(label, command);

  bool shouldDisplay(AtomEvent event) {
    String filePath = event.targetFilePath;
    DartProject project = projectManager.getProjectFor(filePath);
    if (project == null) return false;
    File skyTool = new File.fromPath(
        join(project.directory, 'packages', 'sky', 'sky_tool'));
    return skyTool.existsSync();
  }
}
