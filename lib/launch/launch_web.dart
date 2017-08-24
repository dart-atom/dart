library atom.launch_web;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:logging/logging.dart';

import 'launch.dart';
import 'launch_serve.dart';

import '../browser.dart';
import '../state.dart';
import '../debug/chrome_debugger.dart';

final Logger _logger = new Logger('atom.launch.web');

// TODO: option?
bool debugging = true;
bool pub_serve_check = true;

class WebLaunchType extends LaunchType {
  static void register(LaunchManager manager) =>
      manager.registerLaunchType(new WebLaunchType());

  WebLaunchType() : super('web');

  bool canLaunch(String path, LaunchData data) => path.endsWith('.html');

  Future<Launch> performLaunch(LaunchManager manager, LaunchConfiguration configuration) {
    Browser browser = deps[BrowserManager].browser;
    if (browser == null) {
      atom.notifications.addWarning('No browser configured.');
      return new Future.value();
    }

    // TODO add a config for this (pub_serve_check or url)
    String root = 'http://localhost:8084';
    if (pub_serve_check) {
      // Find pub serve for 'me'.
      ServeLaunch pubServe = manager.launches.firstWhere((l) =>
          l is ServeLaunch &&
          l.isRunning &&
          l.launchConfiguration.projectPath == configuration.projectPath,
          orElse: () => null);

      if (pubServe == null) {
        atom.notifications.addWarning('No pub serve launch found.');
        return new Future.value();
      }
      root = pubServe.root;
    }

    Map yamlArgs = configuration.typeArgs['args'];
    List<String> args = browser.execArgsFromYaml(yamlArgs);
    String htmlFile = configuration.shortResourceName;
    if (htmlFile.startsWith('web/')) {
      htmlFile = htmlFile.substring(4);
    }

    if (!debugging) {
      args.add('$root/$htmlFile');
    }

    ProcessRunner runner = new ProcessRunner.underShell(browser.path, args: args);

    Launch launch = new Launch(manager, this, configuration,
      configuration.shortResourceName,
      killHandler: () => runner.kill(),
      title: configuration.shortResourceName
    );
    manager.addLaunch(launch);

    runner.execStreaming();
    runner.onStdout.listen((str) => launch.pipeStdio(str));
    runner.onStderr.listen((str) => launch.pipeStdio(str, error: true));
    runner.onExit.then((code) => launch.launchTerminated(code));

    if (debugging) {
      String debugHost = 'localhost:${yamlArgs['remote-debugging-port']}';
      ChromeDebugger.connect(launch, configuration, debugHost, root, htmlFile)
          .catchError((e) {
        launch.pipeStdio('Unable to connect to chrome.\n', error: true);
      });
    }

    return new Future.value(launch);
  }

  String getDefaultConfigText() => '''
# Additional args for browser.
args:
  remote-debugging-port: 9222
  user-data-dir: ${fs.tmpdir}/dartlang-dbg-host
  no-default-browser-check: true
  no-first-run: true
''';
}
