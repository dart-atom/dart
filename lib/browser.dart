library atom.browser;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/process.dart';
import 'package:atom/utils/disposable.dart';

import 'impl/debounce.dart';
import 'state.dart';

class BrowserManager implements Disposable {
  final String browserKey = '${pluginId}.debugBrowserLocation';
  final List<StreamSubscription> subs = [];

  String get browserPath => atom.config.getValue(browserKey);

  Browser _browser;
  Browser get browser => _browser;

  String _version;
  String get version => _version;

  StreamController<Browser> _onBrowserChangeController =
      new StreamController.broadcast(sync: true);
  StreamController<String> _onVersionChangeController =
      new StreamController.broadcast(sync: true);

  Stream<Browser> get onBrowserChange => _onBrowserChangeController.stream;
  Stream<String> get onBrowserVersionChange => _onVersionChangeController.stream;

  BrowserManager() {
    void update(String path) {
      _browser = new Browser(path);
      _onBrowserChangeController.add(_browser);
      // Now get version if possible.
      _browser.getVersion().then((version) {
        _version = version;
        _onVersionChangeController.add(version);
      });
    }
    subs.add(atom.config.onDidChange(browserKey)
        .transform(new Debounce(new Duration(seconds: 1)))
        .listen(update));
    if (browserPath != null) {
      update(browserPath);
    }
  }

  void dispose() {
    subs.forEach((sub) => sub.cancel());
  }
}

class Browser {
  final String path;

  Browser(this.path);

  Future<String> getVersion() {
    if (!fs.existsSync(path) || !fs.statSync(path).isFile()) {
      return new Future.value(null);
    }
    ProcessRunner runner =
        new ProcessRunner.underShell(path, args: ['--version']);
    runner.execStreaming();

    StringBuffer buf = new StringBuffer();
    runner.onStdout.listen((str) => buf.write(str));

    return runner.onExit.then((_) => buf.toString());
  }
}
