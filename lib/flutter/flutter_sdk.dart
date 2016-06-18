
import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/atom_utils.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/process.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../impl/debounce.dart';
import '../jobs.dart';
import '../state.dart' show sdkManager;
import 'flutter.dart';

final String _prefKey = 'flutter.flutterRoot';

final Logger _logger = new Logger('flutter.sdk');

class FlutterSdkManager implements Disposable {
  StreamController<FlutterSdk> _controller = new StreamController.broadcast(sync: true);

  StreamSubscription _prefSub;
  Disposables _disposables = new Disposables();

  FlutterSdk _sdk;

  FlutterSdkManager() {
    // Load the existing setting and initiate auto-discovery if necessary.
    String currentPath = atom.config.getValue(_prefKey);

    if (currentPath == null || currentPath.isEmpty) {
      if (Flutter.hasFlutterPlugin()) {
        tryToAutoConfigure(complainOnFailure: false);
      }
    } else {
      FlutterSdk sdk = new FlutterSdk.fromPath(currentPath);
      if (sdk != null && sdk.isValidSdk) {
        _setSdk(sdk);
      }
    }

    // Listen to changes to the sdk pref setting; debounce the changes.
    _prefSub = atom.config.onDidChange(_prefKey)
      .transform(new Debounce(new Duration(seconds: 1)))
      .listen((value) => _setSdkPath(value));

    if (Flutter.hasFlutterPlugin()) {
      _disposables.add(atom.commands.add('atom-workspace', 'flutter:auto-locate-flutter-sdk', (_) {
        new SdkLocationJob(this).schedule();
      }));
      _disposables.add(atom.commands.add('atom-workspace', 'flutter:show-flutter-sdk-info', (_) {
        showInstallationInfo();
      }));
      _disposables.add(atom.commands.add('atom-workspace', 'flutter:version', (_) {
        showVersionInfo();
      }));
    }
  }

  Future tryToAutoConfigure({bool complainOnFailure: true}) {
    return _discoverSdk().then((String sdkPath) {
      if (sdkPath != null) {
        atom.config.setValue(_prefKey, sdkPath);
        return true;
      } else {
        if (complainOnFailure) {
          atom.notifications.addWarning('Unable to auto-locate a Flutter SDK.');
        }
        return false;
      }
    });
  }

  bool get hasSdk => _sdk != null;

  FlutterSdk get sdk => _sdk;

  Stream<FlutterSdk> get onSdkChange => _controller.stream;

  void _setSdkPath(String path) {
    _setSdk(new FlutterSdk.fromPath(path), verbose: true);
  }

  void _setSdk(FlutterSdk sdk, {bool verbose: false}) {
    if (sdk != null && !sdk.isValidSdk) {
      String path = sdk.path;

      if (verbose) {
        if (path == null || path.isEmpty) {
          atom.notifications.addWarning('No Flutter SDK configured.');
        } else {
          atom.notifications.addWarning(
            'Unable to locate Flutter SDK.',
            description: 'No SDK at ${path}.');
        }
      }

      sdk = null;
    }

    if (sdk == _sdk) return;

    _sdk = sdk;

    if (_sdk != null) {
      _logger.info('Using Flutter SDK at ${_sdk.path}.');

      if (verbose) {
        atom.notifications.addSuccess("Flutter SDK found at ${sdk.path}.");
      }

      if (sdkManager.noSdkPathConfigured) {
        // Set up a Dart SDK.
        String dartSdkPath = sdk.dartSdkPath;
        if (dartSdkPath != null) {
          sdkManager.setSdkPath(dartSdkPath);
        }
      }
    }

    _controller.add(_sdk);
  }

  void dispose() {
    if (_prefSub != null) _prefSub.cancel();
    _disposables.dispose();
  }

  void showInstallationInfo({bool justVersion: false}) {
    String description;

    if (!hasSdk) {
      description = "No Flutter SDK configured.";
    } else {
      description = "Using Flutter SDK at ${sdk.path}.";
    }

    Notification notification;

    var autoLocate = () {
      notification.dismiss();
      new SdkLocationJob(this).schedule();
    };

    var openSettings = () {
      notification.dismiss();
      atom.workspace.openConfigPage(packageID: 'dartlang');
    };

    notification = atom.notifications.addSuccess('Flutter SDK info',
      detail: description,
      dismissable: true,
      buttons: [
        new NotificationButton('Auto-locate SDK', autoLocate),
        new NotificationButton('Plugin Settings…', openSettings)
      ]
    );

    if (hasSdk) {
      sdk.flutterTool.runInJob(['--version']);
    }
  }

  void showVersionInfo() {
    if (hasSdk) {
      sdk.flutterTool.runInJob(['--version']);
    } else {
      atom.notifications.addSuccess('Flutter SDK info',
        detail: 'No Flutter SDK configured.',
        dismissable: true
      );
    }
  }
}

Future<String> _discoverSdk() {
  // // Look for FLUTTER_ROOT.
  // String envVar = env('FLUTTER_ROOT');
  // if (envVar != null && envVar.isNotEmpty) {
  //   return new Future.value(envVar.trim());
  // }

  if (isMac) {
    // /bin/bash -c "which flutter"
    return which('flutter').then((result) {
      return _resolveSdkFromFlutterPath(result);
    }).catchError((e) {
      return null;
    });
  } else if (isWindows) {
    return which('flutter', isBatchScript: true).then((result) {
      return _resolveSdkFromFlutterPath(result);
    }).catchError((e) {
      return null;
    });
  } else {
    return which('flutter').then((String result) {
      return _resolveSdkFromFlutterPath(result);
    }).catchError((e) {
      return null;
    });
  }
}

String _resolveSdkFromFlutterPath(String path) {
  if (path == null) return null;

  // Don't resolve to the pub cache.
  if (isWindows) {
    if (path.contains(r'Pub\Cache')) return null;
  } else {
    if (path.contains(r'/.pub-cache/')) return null;
  }

  File vmFile = new File.fromPath(path.trim());
  return vmFile.getParent().getParent().path;
}

class FlutterSdk {
  final String path;

  FlutterSdk.fromPath(this.path);

  bool get isValidSdk => new File.fromPath(flutterToolPath).existsSync();

  String get flutterToolPath {
    return fs.join(path, 'bin', isWindows ? 'flutter.bat' : 'flutter');
  }

  FlutterTool get flutterTool => new FlutterTool(this, flutterToolPath);

  /// Return the path to the Dart SDK contained within the Flutter SDK, if the
  /// Dart SDK is present.
  String get dartSdkPath {
    String p = fs.join(path, 'bin', 'cache', 'dart-sdk');
    if (new Directory.fromPath(p).existsSync()) return p;
    return null;
  }

  String toString() => "flutter sdk at ${path}";
}

class FlutterTool {
  final FlutterSdk sdk;
  final String toolPath;

  FlutterTool(this.sdk, this.toolPath);

  ProcessRunner runRaw(List<String> args, {String cwd, bool startProcess: true}) {
    ProcessRunner runner =
        new ProcessRunner.underShell(toolPath, args: args, cwd: cwd);
    if (startProcess) runner.execStreaming();
    return runner;
  }

  Future runInJob(List<String> args, {String cwd, String title}) {
    Job job = new _FlutterToolJob(sdk, cwd, args);
    return job.schedule();
  }
}

class _FlutterToolJob extends Job {
  final FlutterSdk sdk;
  final String cwd;
  List<String> _args;
  final String title;

  _FlutterToolJob(this.sdk, this.cwd, List<String> args, {
    this.title
  }) : super('Flutter ${args.first}') {
    _args = args;
  }

  Object get schedulingRule => cwd;

  bool get quiet => true;

  Future run() {
    ProcessNotifier notifier = new ProcessNotifier(title ?? name);
    ProcessRunner runner = _run();
    return notifier.watch(runner);
  }

  ProcessRunner _run() {
    ProcessRunner runner = new ProcessRunner.underShell(sdk.flutterToolPath,
        args: _args, cwd: cwd);
    runner.execStreaming();
    return runner;
  }
}

class SdkLocationJob extends Job {
  final FlutterSdkManager sdkManager;

  SdkLocationJob(this.sdkManager) : super('Auto locate SDK');

  Future run() {
    sdkManager.tryToAutoConfigure(complainOnFailure: true);
    return new Future.delayed(new Duration(milliseconds: 500));
  }
}
