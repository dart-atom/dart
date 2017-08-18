
/// A console output view.
library atom.console;

import 'dart:async';
import 'dart:html' as html show Element, ScrollAlignment;

import 'package:atom/atom.dart';
import 'package:atom/node/shell.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';

import '../atom_statusbar.dart';
import '../elements.dart';
import '../state.dart';
import '../views.dart';
import 'launch.dart';

class ConsoleController extends DockedViewManager<ConsoleView> {
  static const consoleURIPrefix = 'atom://dartlang/console';

  ConsoleStatusElement statusElement;

  ConsoleController() : super(consoleURIPrefix) {
    statusElement = new ConsoleStatusElement(this, false);

    disposables.add(atom.commands.add(
        'atom-workspace', '${pluginId}:toggle-console', (_) {
      _toggleViews();
    }));

    disposables.add(new DoubleCancelCommand(_handleDoubleEscape));

    subs.add(launchManager.onLaunchAdded.listen(_launchAdded));
    subs.add(launchManager.onLaunchRemoved.listen(_launchRemoved));
    subs.add(launchManager.onLaunchActivated.listen(_launchActivated));
    subs.add(launchManager.onLaunchTerminated.listen(_launchTerminated));
  }

  void initStatusBar(StatusBar statusBar) {
    statusElement._init(statusBar);
  }

  String launchId(Launch launch) => '${launch.id}';

  void _launchAdded(Launch launch) {
    showView(id: launchId(launch), data: launch);
  }

  void _launchRemoved(Launch launch) {
    removeView(id: launchId(launch));
  }

  void _launchActivated(Launch launch) {
    showView(id: launchId(launch));
  }

  void _launchTerminated(Launch launch) {
    // Update tab title
    new Future.delayed(const Duration(milliseconds: 300), () {
      DockedView v = viewFromId(launchId(launch));
      v?.item?.title = v.label;
    });
  }

  void _toggleViews() {
    if (views.isEmpty) return;
    views.values.forEach((v) => showView(id: v.id));
  }

  void _handleDoubleEscape() {
    for (Launch launch in launchManager.launches.toList()) {
      if (launch.isTerminated) {
        launchManager.removeLaunch(launch);
      }
    }
  }

  void dispose() {
    super.dispose();
    statusElement.dispose();
  }

  ConsoleView instantiateView(String id, [dynamic data]) =>
      new ConsoleView(id, data as Launch);
}

class ConsoleView extends DockedView {
  // Only show a set amount of lines of output.
  static const _maxLines = 300;

  final CoreElement toolbar;
  final Launch launch;

  StreamSubscriptions _subs = new StreamSubscriptions();

  CoreElement output;
  String _lastText = '';

  CoreElement _terminateButton;
  CoreElement _reloadButton;
  CoreElement _observatoryButton;

  ConsoleView(String id, this.launch)
      : toolbar = div(),
        super(id, div()) {
    root.toggleClass('console-view');
    root.add([
      div(c: 'button-bar')..flex()..add([
        toolbar,
      ])]);

    toolbar.toggleClass('btn-group');
    toolbar.toggleClass('btn-group-sm');
    content.toggleClass('tab-scrollable-container');
    output = content.add(
      new CoreElement('pre', classes: 'console-line tab-scrollable')
    );

    _subs.add(launchManager.onLaunchTerminated.listen(_launchTerminated));
    _subs.add(launchManager.onLaunchRemoved.listen(_launchRemoved));

    root.listenForUserCopy();

    // Allow the text in the console to be selected.
    output.element.tabIndex = -1;

    _subs.add(launch.onStdio.listen((TextFragment text) {
      _emitText(text.text, error: text.error, subtle: text.subtle, highlight: text.highlight);
    }));

    // Terminate
    if (launch.canKill()) {
      _terminateButton = toolbar.add(
        button(text: 'Stop', c: 'btn icon icon-primitive-square')
      );
      _terminateButton.tooltip = 'Terminate process';
      _terminateButton.click(() => launch.kill());
    }

    // Reload
    if (launch.supportsRestart) {
      _reloadButton = toolbar.add(
        button(text: 'Reload', c: 'btn icon icon-sync')
      );
      _reloadButton.tooltip = 'Reload application';
      _reloadButton.click(() {
        atom.workspace.saveAll();
        launch.restart();
      }, () {
        atom.workspace.saveAll();
        launch.restart(fullRestart: true);
      });
    }

    // Configure
    if (launch.launchConfiguration != null) {
      CoreElement e = toolbar.add(
        button(text: 'Configure', c: 'btn icon icon-gear')
      );
      e.tooltip = 'Configure this application launch';
      e.click(() {
        atom.workspace.openPending(launch.launchConfiguration.configYamlPath);
      });
    }

    // Observatory
    launch.servicePort.observe(_watchServicePort);

    // Emit a header.
    String header;
    if (launch.title != null) {
      header = launch.title;
    } else {
      header = launch.name;
    }
    header += ' • ${launch.subtitle}\n';
    _emitText(header);
  }

  String get defaultLocation => 'bottom';

  String get label => "${!launch.isTerminated ? '• ' : ''}" +
      launch.launchConfiguration?.shortResourceName ?? launch.name;

  void _watchServicePort(int port) {
    if (!launch.isRunning) return;

    if (_observatoryButton != null && port == null) {
      _observatoryButton.dispose();
      _observatoryButton = null;
    } else if (_observatoryButton == null && port != null) {
      _observatoryButton = toolbar.add(
        button(text: 'Observatory', c: 'btn icon icon-dashboard')
      );
      _observatoryButton.tooltip = 'Open the Observatory';
      _observatoryButton.click(() {
        shell.openExternal('http://localhost:${launch.servicePort}/');
      });
    }
  }

  void _launchTerminated(Launch l) {
    if (launch == l) {
      if (!_lastText.endsWith('\n')) _emitText('\n');
      _emitText('process finished • exit code ${launch.exitCode}');
      _terminateButton?.disabled = true;
      _reloadButton?.disabled = true;
      _observatoryButton?.disabled = true;
    }
  }

  void _launchRemoved(Launch l) {
    if (launch == l) {
      _subs.cancel();
    }
  }

  void handleClose() {
    if (launch.isTerminated) {
      launchManager.removeLaunch(launch);
    }
  }

  String _text = '';
  Timer _timer;

  void _emitText(String str, {bool error: false, bool subtle: false, bool highlight: false}) {
    _lastText = str;

    _text += str;

    if (_timer == null) {
      _timer = new Timer(new Duration(milliseconds: 250), () {
        _timer = null;

        List<String> lines = _text.split('\n');
        if (lines.length > _maxLines) {
          lines.removeRange(0, lines.length - _maxLines);
        }
        String newText = lines.join('\n');
        if (_text.endsWith('\n')) {
          newText += '\n';
        }
        _text = newText;

        if (output.element.children.isEmpty) {
          html.Element span = new html.Element.span()..text = newText;
          output.element.children.add(span);
          span.scrollIntoView(html.ScrollAlignment.BOTTOM);
        } else {
          html.Element span = output.element.children.elementAt(0);
          span.text = newText;
          span.scrollIntoView(html.ScrollAlignment.BOTTOM);
        }
      });
    }
  }
}

class ConsoleStatusElement implements Disposable {
  final ConsoleController parent;
  bool _showing;
  StreamSubscriptions subs = new StreamSubscriptions();

  Tile statusTile;

  CoreElement _element;
  CoreElement _badgeSpan;

  ConsoleStatusElement(this.parent, this._showing) {
    subs.add(launchManager.onLaunchAdded.listen(_handleLaunchesChanged));
    subs.add(launchManager.onLaunchTerminated.listen(_handleLaunchesChanged));
    subs.add(launchManager.onLaunchRemoved.listen(_handleLaunchesChanged));
  }

  bool isShowing() => _showing;

  void show() {
    _element.element.style.display = 'inline-block';
    _showing = true;
  }

  void hide() {
    _element.element.style.display = 'none';
    _showing = false;
  }

  void dispose() {
    if (statusTile != null) statusTile.destroy();
    subs.cancel();
  }

  void _init(StatusBar statusBar) {
    _element = div(c: 'dartlang process-status-bar')..inlineBlock()..add([
      _badgeSpan = span(c: 'badge')
    ]);

    // Show all hidden views - make sure one is activated.
    _element.click(parent._toggleViews);

    statusTile = statusBar.addLeftTile(item: _element.element, priority: -99);

    if (!isShowing()) {
      _element.element.style.display = 'none';
    }

    _handleLaunchesChanged();
  }

  void _handleLaunchesChanged([Launch _]) {
    if (_element == null) return;

    List<Launch> launches = launchManager.launches;
    int count = launches.length;

    if (count > 0) {
      if (!isShowing()) show();
      _badgeSpan.text = '${count} ${pluralize('process', count)}';
    } else {
      hide();
      _badgeSpan.text = 'no processes';
    }
  }
}
