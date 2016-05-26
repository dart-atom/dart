import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:atom/utils/disposable.dart';

import '../../impl/pub.dart' show dotPackagesFileName;
import '../dartino.dart';
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

  String get samplesRoot => resolvePath('dart/examples');

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
    if (device == null) {
      launch.launchTerminated(-1, quiet: true);
      return;
    }
    if (!await device.launchSOD(this, launch)) {
      _debugDaemon?.dispose();
    }
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
  void promptOptIntoAnalytics() {
    // ignored
  }

  @override
  void showDocs() {
    atom.notifications.addInfo('no docs yet');
  }

  /// Launch the debug daemon if not already running.
  /// Return `true` if successfully launched and connected to the device
  /// or if already running, else return `false`.
  Future<bool> startDebugDaemon(DartinoLaunch launch) async {
    if (_debugDaemon != null) return true;
    _DebugDaemon daemon = new _DebugDaemon(this);
    if (!await daemon.start(launch)) return false;
    dartino.disposables.add(daemon);
    _debugDaemon = daemon;
    return true;
  }
}

/// The current debug daemon, or `null` if one is not running.
_DebugDaemon _debugDaemon;

class _DebugDaemon implements Disposable {
  final SodRepo sdk;
  ProcessRunner runner;

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

    // Start the daemon process and wait for a connection message
    Completer<bool> connected = new Completer<bool>();
    StringBuffer out = new StringBuffer();
    try {
      runner.execStreaming().then((int exitCode) {
        if (connected.isCompleted) {
          atom.notifications.addInfo('Device disconnected',
              detail: '$daemonPath\n$out\nexit code $exitCode');
        } else {
          atom.notifications.addError('Failed to connect to device',
              detail: '$daemonPath\n$out\nexit code $exitCode');
          connected.complete(false);
        }
        dispose();
      });
    } catch (e, s) {
      atom.notifications
          .addError('Failed to start daemon', detail: '$daemonPath\n$e\n$s');
      return false;
    }
    void processDaemonOutput(String data) {
      out.write(data);
      launch.pipeStdio('sdbgd: $data\n');
      if (out.toString().contains('Connected to USB device.')) {
        connected.complete(true);
      }
    }
    runner.onStdout.listen(processDaemonOutput);
    runner.onStderr.listen(processDaemonOutput);
    return connected.future;
  }

  @override
  void dispose() {
    runner?.kill();
    runner = null;
    if (_debugDaemon == this) _debugDaemon = null;
  }
}
