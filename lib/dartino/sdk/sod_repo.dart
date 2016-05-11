import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:atom/utils/disposable.dart';

import '../../impl/pub.dart' show dotPackagesFileName;
import '../dartino_util.dart';
import '../device/device.dart';
import '../launch_dartino.dart';
import 'sdk.dart';

/// The SOD repository as an SDK
class SodRepo extends Sdk {
  /// Return a new instance if an SDK could exist at the given [path]
  /// or `null` if not. Clients should call [validate] on any returned sdk
  /// to ensure that it is a valid SDK.
  static SodRepo forPath(String path) {
    var sdk = new SodRepo(path);
    return sdk.existsSync('third_party/openocd/README.md') ? sdk : null;
  }

  /// Prompt the user for where to install a new SDK, then do it.
  static Future promptInstall([_]) async {
    // String path =
    await Sdk.promptInstallPath('SOD repository', 'sod/repo');
    atom.notifications.addError('Not implemented yet');
  }

  SodRepo(String sdkRoot) : super(sdkRoot);

  String get name => 'SOD repository';

  String get sodUtil => resolvePath('dart/bin/sod.dart');

  String get debugUtil => resolvePath('third_party/lk/tools/sdbg');

  /// Compile the application and return the path of the binary to deploy.
  /// If there is a problem, notify the user and return `null`.
  Future<String> compile(DartinoLaunch launch) async {
    String srcPath = launch.primaryResource;
    String dstPath = srcPath.substring(0, srcPath.length - 5) + '.snap';

    int exitCode = await launch.run('make',
        args: [dstPath],
        cwd: sdkRoot,
        isLast: false,
        message: 'Building $srcPath ...');
    if (exitCode != 0) {
      atom.notifications.addError('Failed to compile application',
          detail: 'Failed to compile.\n'
              '$srcPath\n'
              'See console for more.');
      return null;
    }
    return dstPath;
  }

  @override
  Future<bool> createNewProject(String projectPath) async {
    // TODO(danrubel) implement sod create project in sod cmdline utility then
    // call it from here.
    try {
      var dir = new Directory.fromPath(projectPath);
      if (!dir.existsSync()) await dir.create();
      if (!dir.getEntriesSync().isEmpty) {
        atom.notifications.addError('Project already exists',
            detail: projectPath, dismissable: true);
        return false;
      }
      dartino.createDartinoYaml(dir);
    } catch (e, s) {
      atom.notifications.addError('Failed to create new project',
          detail: '$projectPath\n$e\n$s', dismissable: true);
      return false;
    }
    return true;
  }

  @override
  Future launch(DartinoLaunch launch) async {
    Device device = await Device.forLaunch(this, launch);
    if (device == null) return;
    device.launchSOD(this, launch);
  }

  @override
  String packageRoot(projDir) {
    if (projDir == null) return null;
    String localSpecFile = fs.join(projDir, dotPackagesFileName);
    if (fs.existsSync(localSpecFile)) return localSpecFile;
    return resolvePath('third_party/dartino/internal/dartino-sdk.packages');
  }

  @override
  bool validate({bool quiet: false}) {
    if (!existsSync('third_party/lk/platform/stm32f7xx/init.c')) {
      if (!quiet) {
        dartino.promptSetSdk('Invalid SOD repository specified.',
            detail: 'It appears that SOD was installed'
                ' using git clone rather than gclient.');
      }
      return false;
    }
    return true;
  }

  @override
  void showDocs() {
    atom.notifications.addInfo('no docs yet');
  }

  /// Launch the debug daemon if not already running.
  /// Return the [LkShell] used to interact with the device
  /// or `null` if the daemon could not connect to the device.
  Future<LkShell> startDebugDaemon(DartinoLaunch launch) async {
    if (_debugDaemon != null) return _debugDaemon.shell;
    _DebugDaemon daemon = new _DebugDaemon(this);
    if (!await daemon.start(launch)) return null;
    dartino.disposables.add(daemon);
    _debugDaemon = daemon;
    return _debugDaemon.shell;
  }
}

/// The current debug daemon, or `null` if one is not running.
_DebugDaemon _debugDaemon;

class _DebugDaemon implements Disposable {
  final SodRepo sdk;
  ProcessRunner runner;
  LkShell shell;

  _DebugDaemon(this.sdk);

  String get daemonPath => sdk.resolvePath('third_party/lk/tools/sdbgd');

  Future<bool> start(DartinoLaunch launch) async {
    if (!fs.existsSync(daemonPath)) {
      atom.notifications
          .addError('Cannot find debug daemon', detail: daemonPath);
      return false;
    }
    launch.pipeStdio('Launching debug daemon...\n\$ $daemonPath\n');
    runner = new ProcessRunner(daemonPath);
    Future<ProcessResult> future;
    try {
      future = runner.execSimple();
      ProcessResult result = await future
          //TODO(danrubel) need better way to determine if device connected
          .timeout(new Duration(milliseconds: 1500), onTimeout: () => null);
      if (result != null) {
        atom.notifications.addError('Failed to connect to device',
            detail: '$daemonPath\n${result.stderr}\n${result.stdout}');
        return false;
      }
    } catch (e, s) {
      atom.notifications
          .addError('Failed to start daemon', detail: '$daemonPath\n$e\n$s');
      return false;
    }
    future.then((ProcessResult result) {
      String detail = '${result.stderr}\n${result.stdout}'.trim();
      if (detail == 'Connected to USB device.') detail == null;
      atom.notifications.addInfo('Device disconnected', detail: detail);
      if (_debugDaemon == this) _debugDaemon = null;
      dispose();
    });
    shell = new LkShell().._start(launch);
    return true;
  }

  @override
  void dispose() {
    shell?.dispose();
    shell = null;
    runner?.kill();
    runner = null;
  }
}

class LkShell implements Disposable {
  ProcessRunner runner;
  DartinoLaunch launch;

  void _start(DartinoLaunch launch) {
    this.launch = launch;
    runner = new ProcessRunner('netcat', args: ['localhost', '9092']);
    runner.onStdout.listen(launch.pipeStdio);
    runner.onStderr.listen((str) => launch.pipeStdio(str, error: true));
    runner.execStreaming().then((int exitCode) {
      runner = null;
      launch.pipeStdio('netcat exit code $exitCode');
    });
  }

  void write(String command) {
    if (runner == null) {
      launch.pipeStdio('netcat terminated\nfailed to send $command\n',
          error: true);
      return;
    }
    runner.write(command);
  }

  @override
  void dispose() {
    runner?.kill();
    runner = null;
  }
}
