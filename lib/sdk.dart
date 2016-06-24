// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.sdk;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/atom_utils.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import 'flutter/flutter_sdk.dart' show FlutterSdkManager;
import 'impl/debounce.dart';
import 'jobs.dart';
import 'state.dart';

final String _prefPath = '${pluginId}.sdkLocation';

final Logger _logger = new Logger('sdk');

// Use cases:

// cold start
// - we see no sdk value
// - try and auto-locate
// - display message on success (no message on failure)

// start up, w/ sdk value
// - validate it
// - if good, create an sdk
// - on bad sdk, no message, no sdk created

// explicit auto-locate sdk command
// - try and auto locate
// - message on success; message in failure

// user types in the settings field
// - buffer changes - 2 second delay?
// - if we auto-locate, display a success message
// - if no, display a failure message

// TODO: status line contribution for a mis-configured sdk

class SdkManager implements Disposable {
  /// The minimum version for an installed SDK or `null` if unspecified.
  static Version _minVersion;

  static void set minVersion(Version minVersion) {
    if (_minVersion == null || _minVersion < minVersion) {
      _minVersion = minVersion;
    }
  }

  StreamController<Sdk> _controller =
      new StreamController.broadcast(sync: true);

  StreamSubscription _prefSub;
  Disposables _commands = new Disposables();

  Sdk _sdk;

  SdkManager() {
    // Load the existing setting and initiate auto-discovery if necessary.
    String currentPath = atom.config.getValue(_prefPath);

    if (currentPath == null || currentPath.isEmpty) {
      new Future.delayed(new Duration(seconds: 4), () {
        if (!sdkManager.hasSdk) tryToAutoConfigure();
      });
    } else {
      Sdk sdk = new Sdk.fromPath(currentPath);
      if (sdk != null && sdk.isValidSdk) _setSdk(sdk);
    }

    // Listen to changes to the sdk pref setting; debounce the changes.
    _prefSub = atom.config
        .onDidChange(_prefPath)
        .transform(new Debounce(new Duration(seconds: 1)))
        .listen((value) => _setSdkPath(value));

    _commands.add(atom.commands.add('atom-workspace', 'dartlang:auto-locate-sdk', (_) {
      new SdkLocationJob(sdkManager).schedule();
    }));
  }

  bool get hasSdk => _sdk != null;

  Sdk get sdk => _sdk;

  bool get noSdkPathConfigured {
    String currentPath = atom.config.getValue(_prefPath);
    return currentPath == null || currentPath.isEmpty;
  }

  void showNoSdkMessage({String messagePrefix}) {
    String message = messagePrefix == null
        ? 'No Dart SDK found.' : '${messagePrefix}: no Dart SDK found.';
    atom.notifications.addInfo(message,
        description: 'You can configure your SDK location in Settings > '
            'Packages > dart-lang > Settings.',
        dismissable: true);
  }

  Future<bool> tryToAutoConfigure({bool verbose: true}) {
    return new SdkDiscovery().discoverSdk().then((String sdkPath) {
      if (sdkPath != null) {
        atom.config.setValue(_prefPath, sdkPath);
        return true;
      } else {
        if (verbose) {
          atom.notifications.addWarning('Unable to auto-locate a Dart SDK.');
        }
        return false;
      }
    });
  }

  Stream<Sdk> get onSdkChange => _controller.stream;

  void setSdkPath(String path) {
    atom.config.setValue(_prefPath, path);
  }

  void _setSdkPath(String path) {
    _setSdk(new Sdk.fromPath(path), verbose: true);
  }

  Future _setSdk(Sdk sdk, {bool verbose: false}) async {
    if (sdk != null && sdk.isNotValidSdk) {
      String path = sdk.directory.path;

      if (verbose) {
        if (path == null || path.isEmpty) {
          atom.notifications.addWarning('No Dart SDK configured.');
        } else {
          atom.notifications.addWarning(
              'Unable to locate Dart SDK.', description: 'No SDK at ${path}.');
        }
      }

      sdk = null;
    }

    if (sdk == _sdk) return;

    _sdk = sdk;

    if (_sdk != null) {
      String version = await _sdk.getVersion();
      _logger.info('version ${version} (${_sdk.path})');

      if (verbose) {
        atom.notifications.addSuccess(
          "Found Dart SDK version ${version}.",
          detail: sdk.directory.path
        );
      }

      _verifyMinVersion(_sdk, version);

      _controller.add(_sdk);
    } else {
      _controller.add(_sdk);
    }
  }

  void dispose() {
    _prefSub.cancel();
    _commands.dispose();
  }

  bool _alreadyWarned = false;

  void _verifyMinVersion(Sdk currentSdk, String version) {
    if (version == null) return;

    try {
      Version installedVersion = new Version.parse(version);
      if (_minVersion != null && installedVersion < _minVersion) {
        if (!_alreadyWarned) {
          _alreadyWarned = true;
          atom.notifications.addWarning(
              'SDK version ${installedVersion} is older than the recommended '
              'version of ${_minVersion}. Please visit www.dartlang.org to '
              'download a recent SDK.',
              detail: 'Using SDK at ${currentSdk.path}.',
              dismissable: true);
        }
      }
    } catch (e) {}
  }
}

class Sdk {
  final Directory directory;

  Sdk(this.directory);

  factory Sdk.fromPath(String path) {
    if (path == null) return null;
    return new Sdk(new Directory.fromPath(fs.resolveTilde(path)));
  }

  bool get isValidSdk =>
      directory.getFile('version').existsSync() &&
      directory.getSubdirectory('bin').existsSync();

  bool get isNotValidSdk => !isValidSdk;

  String get path => directory.path;

  String get binPath => fs.join(path, 'bin');

  Future<String> getVersion() {
    File file = directory.getFile('version');
    if (file.existsSync()) {
      return file.read().then((data) => data.trim());
    } else {
      return new Future.value(null);
    }
  }

  File get dartVm {
    if (isWindows) {
      return new File.fromPath(fs.join(directory, 'bin', 'dart.exe'));
    } else {
      return new File.fromPath(fs.join(directory, 'bin', 'dart'));
    }
  }

  String getSnapshotPath(String snapshotName) {
    File file = new File.fromPath(
        fs.join(directory, 'bin', 'snapshots', snapshotName));
    return file.path;
  }

  /// Execute the given SDK binary (a command in the `bin/` folder). [cwd] can
  /// be either a [String] or a [Directory].
  ProcessRunner execBin(String binName, List<String> args, {
    cwd, bool startProcess: true
  }) {
    if (cwd is Directory) cwd = cwd.path;
    String command = getToolPath(binName);
    ProcessRunner runner =
        new ProcessRunner.underShell(command, args: args, cwd: cwd);
    if (startProcess) runner.execStreaming();
    return runner;
  }

  /// Execute the given SDK binary (a command in the `bin/` folder). [cwd] can
  /// be either a [String] or a [Directory].
  Future<ProcessResult> execBinSimple(String binName, List<String> args, {cwd}) {
    if (cwd is Directory) cwd = cwd.path;
    String command = getToolPath(binName);
    return new ProcessRunner.underShell(command, args: args, cwd: cwd).execSimple();
  }

  // Get the full, platform dependent name to a tool in the `bin/` directory.
  String getToolPath(String toolName) {
    return fs.join(directory, 'bin', isWindows ? '${toolName}.bat' : toolName);
  }

  String toString() => directory.getPath();
}

class SdkDiscovery {
  /// Try and auto-discover an SDK based on platform specific heuristics. This
  /// will return `null` if no SDK is found.
  Future<String> discoverSdk() {
    return _discoverSdk().then((String sdkPath) {
      return sdkPath != null ? sdkPath : _tryFlutterSdk();
    });
  }

  Future<String> _discoverSdk() {
    if (isMac) {
      return which('dart').then((String result) {
        result = _resolveSdkFromVm(result);
        if (result != null) {
          // On mac, special case for homebrew. Replace the version specific
          // path with the version independent one.
          int index = result.indexOf('/Cellar/dart/');
          if (index != -1 && result.endsWith('/libexec')) {
            result = result.substring(0, index) + '/opt/dart/libexec';
          }
        }
        return result;
      }).catchError((e) {
        return null;
      });
    } else if (isWindows) {
      // TODO: Also use the PATH var?
      return which('dart').then((String result) {
        return _resolveSdkFromVm(result);
      }).catchError((e) {
        return null;
      });
    } else {
      return which('dart').then((String result) {
        return _resolveSdkFromVm(result);
      }).catchError((e) {
        return null;
      });
    }
  }

  /// Return the path to the Dart sdk contained within the Flutter sdk, if
  /// either exist.
  String _tryFlutterSdk() {
    if (!_flutterSdkManager.hasSdk) return null;
    return _flutterSdkManager.sdk.dartSdkPath;
  }

  FlutterSdkManager get _flutterSdkManager => deps[FlutterSdkManager];

  String _resolveSdkFromVm(String vmPath) {
    if (vmPath == null || vmPath.isEmpty) return null;
    File vmFile = new File.fromPath(vmPath.trim());
    // Resolve symlinks.
    vmFile = new File.fromPath(vmFile.getRealPathSync());
    return vmFile.getParent().getParent().path;
  }
}

class SdkLocationJob extends Job {
  final SdkManager sdkManager;

  SdkLocationJob(this.sdkManager) : super('Auto locate SDK');

  bool get quiet => true;

  Future run() {
    sdkManager.tryToAutoConfigure(verbose: true);
    return new Future.delayed(new Duration(milliseconds: 500));
  }
}
