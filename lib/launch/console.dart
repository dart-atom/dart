
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
import '../impl/errors.dart';
import '../state.dart';
import '../views.dart';
import 'launch.dart';

final String _viewGroup = ViewGroup.bottom;

class ConsoleController implements Disposable {
  ConsoleStatusElement statusElement;

  Disposables disposables = new Disposables();
  StreamSubscriptions _subs = new StreamSubscriptions();

  List<View> _allViews = [];
  View _errorsView;

  ConsoleController() {
    statusElement = new ConsoleStatusElement(this, false);

    disposables.add(atom.commands.add(
        'atom-workspace', '${pluginId}:toggle-console', (_) {
      _toggleViews();
    }));

    disposables.add(new DoubleCancelCommand(_handleDoubleEscape));

    _subs.add(launchManager.onLaunchAdded.listen(_launchAdded));
    _subs.add(launchManager.onLaunchRemoved.listen(_launchRemoved));
  }

  void initStatusBar(StatusBar statusBar) {
    statusElement._init(statusBar);
  }

  void _launchAdded(Launch launch) {
    // Check if we should auto-toggle hide the errors view.
    ViewGroup group = viewGroupManager.getGroup(_viewGroup);
    if (group.views.length == 1 && group.hasViewId(errorViewId)) {
      _errorsView = group.getViewById(errorViewId);
      group.removeView(_errorsView);
    }

    ConsoleView view = new ConsoleView(this, launch);
    _allViews.add(view);
    viewGroupManager.addView(_viewGroup, view);
  }

  void _launchRemoved(Launch launch) {
    // Re-show the errors view if we auto-hide it.
    if (_errorsView != null && launchManager.launches.isEmpty) {
      if (!viewGroupManager.hasViewId(errorViewId)) {
        viewGroupManager.addView(_viewGroup, _errorsView);
      }
      _errorsView = null;
    }
  }

  void _toggleViews() {
    if (_allViews.isEmpty) return;

    bool anyActive = _allViews.any((view) => viewGroupManager.isActiveId(view.id));
    bool viewShown = false;

    for (View view in _allViews) {
      if (!viewGroupManager.hasViewId(view.id)) {
        viewShown = true;
        viewGroupManager.addView(_viewGroup, view);
      }
    }

    if (!anyActive) {
      viewGroupManager.activate(_allViews.first);
    } else if (!viewShown) {
      // Hide all the views.
      for (View view in _allViews.toList()) {
        viewGroupManager.removeViewId(view.id);
      }
    }
  }

  void _handleDoubleEscape() {
    for (Launch launch in launchManager.launches.toList()) {
      if (launch.isTerminated) {
        launchManager.removeLaunch(launch);
      }
    }
  }

  void dispose() {
    statusElement.dispose();
    disposables.dispose();
    _subs.cancel();
  }
}

class ConsoleView extends View {
  // Only show a set amount of lines of output.
  static const _maxLines = 300;

  static int _idCount = 0;

  final ConsoleController controller;
  final Launch launch;

  int _launchId;
  StreamSubscriptions _subs = new StreamSubscriptions();

  CoreElement output;
  String _lastText = '';

  CoreElement _terminateButton;
  CoreElement _reloadButton;
  CoreElement _observatoryButton;

  ConsoleView(this.controller, this.launch) {
    _launchId = _idCount++;

    root.toggleClass('console-view');
    toolbar.toggleClass('btn-group');
    toolbar.toggleClass('btn-group-sm');
    content.toggleClass('tab-scrollable-container');
    output = content.add(
      new CoreElement('pre', classes: 'console-line tab-scrollable')
    );

    _subs.add(launchManager.onLaunchActivated.listen(_launchActivated));
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

  String get label => launch.launchConfiguration?.shortResourceName ?? launch.name;

  String get id => 'console.${_launchId}';

  void _launchActivated(Launch l) {
    if (launch == l) {
      if (viewGroupManager.hasViewId(id)) {
        viewGroupManager.activate(this);
      } else {
        viewGroupManager.addView(_viewGroup, this);
      }
    }
  }

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
      tabElement.toggleClass('launch-terminated');
      if (!_lastText.endsWith('\n')) _emitText('\n');
      _emitText('process finished • exit code ${launch.exitCode}');
      _terminateButton?.disabled = true;
      _reloadButton?.disabled = true;
      _observatoryButton?.disabled = true;
    }
  }

  void _launchRemoved(Launch l) {
    if (launch == l) {
      viewGroupManager.removeViewId(id);
      controller._allViews.remove(this);
      _subs.cancel();
    }
  }

  void handleClose() {
    super.handleClose();

    if (launch.isTerminated) launchManager.removeLaunch(launch);
  }

  void dispose() { }

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
