library atom.console;

import 'dart:html' show ScrollAlignment;

import '../atom.dart';
import '../atom_statusbar.dart';
import '../elements.dart';
import '../launch.dart';
import '../state.dart';
import '../utils.dart';
import '../views.dart';

class ConsoleController implements Disposable {
  ConsoleView view;
  ConsoleStatusElement statusElement;

  Disposables disposables = new Disposables();

  ConsoleController() {
    view = new ConsoleView();
    statusElement = new ConsoleStatusElement(this, false);

    disposables.add(atom.commands
        .add('atom-workspace', '${pluginId}:toggle-console', (_) {
      _toggleView();
    }));
  }

  void initStatusBar(StatusBar statusBar) {
    statusElement._init(statusBar);
  }

  void _toggleView() => view.toggle();

  void dispose() {
    view.dispose();
    statusElement.dispose();
    disposables.dispose();
  }
}

// TODO: subtitle of debug | clear | kill

// TODO: close button somewhere

class ConsoleView extends AtomView {
  static bool get autoShowConsole => atom.config.getValue('${pluginId}.autoShowConsole');

  CoreElement title;

  _LaunchController _activeController;
  Map<Launch, _LaunchController> _controllers = {};

  ConsoleView() : super('Console', classes: 'console-view dartlang', prefName: 'Console',
      rightPanel: false, showTitle: false) {
    root.toggleClass('tree-view', false);

    content.add([
      title = div(c: 'console-title-area')
    ]);

    subs.add(launchManager.onLaunchAdded.listen(_launchAdded));
    subs.add(launchManager.onChangedActiveLaunch.listen(_changedActiveLaunch));
    subs.add(launchManager.onLaunchChanged.listen(_launchChanged));
    subs.add(launchManager.onLaunchRemoved.listen(_launchRemoved));
  }

  void _launchAdded(Launch launch) {
    _controllers[launch] = new _LaunchController(this, launch);

    // Auto show when a launch starts.
    if (!isVisible() && autoShowConsole) {
      show();
    }
  }

  void _launchChanged(Launch launch) {
    _activeController.updateStatus();
  }

  void _changedActiveLaunch(Launch launch) {
    if (_activeController != null) _activeController.deactivate();
    _activeController = _controllers[launch];
    if (_activeController != null) _activeController.activate();
  }

  void _launchRemoved(Launch launch) {
    _controllers.remove(launch).dispose();
  }
}

class _LaunchController implements Disposable {
  // Only show a set amount of lines of output.
  static const _max_lines = 200;

  final ConsoleView view;
  final Launch launch;

  CoreElement badge;
  CoreElement element;
  StreamSubscriptions subs = new StreamSubscriptions();

  _LaunchController(this.view, this.launch) {
    badge = view.title.add(span(c: 'badge'));
    badge.click(() => launch.manager.setActiveLaunch(launch));
    updateStatus();

    element = div(c: 'console-line');

    subs.add(launch.onStdout.listen((str) => _emitText(str)));
    subs.add(launch.onStderr.listen((str) => _emitText(str, true)));
  }

  void activate() {
    _updateToggles();
    view.content.add(element.element);
  }

  void updateStatus() {
    _updateToggles();

    if (launch.isRunning) {
      badge.text = '${launch.launchType.type}: ${launch.title}';
    } else {
      badge.toggleClass('launch-terminated');
      badge.text = '${launch.launchType.type}: ${launch.title} [${launch.exitCode}]';
      _emitText('\n');
      _emitBadge('exited with code ${launch.exitCode}',
          launch.errored ? 'error' : 'info');
    }
  }

  void deactivate() {
    _updateToggles();
    element.dispose();
  }

  void _updateToggles() {
    badge.toggleClass('badge-info', launch.isActive && !launch.errored);
    badge.toggleClass('badge-error', launch.isActive && launch.errored);
  }

  void dispose() {
    badge.dispose();
    element.dispose();
    subs.cancel();
  }

  void _emitBadge(String text, String type) {
    CoreElement e = element.add(span(text: text, c: 'badge badge-${type}'));
    if (element.element.parent != null) {
      e.element.scrollIntoView(ScrollAlignment.BOTTOM);
    }
  }

  void _emitText(String str, [bool error = false]) {
    CoreElement e = element.add(span(text: str));
    if (error) e.toggleClass('console-error');

    List children = element.element.children;
    if (children.length > _max_lines) {
      children.remove(children.first);
    }

    if (element.element.parent != null) {
      e.element.scrollIntoView(ScrollAlignment.BOTTOM);
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
    subs.add(launchManager.onLaunchChanged.listen(_handleLaunchesChanged));
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
    _element = div(c: 'dartlang')..inlineBlock()..add([
      _badgeSpan = span(c: 'badge')
    ]);

    _element.click(parent._toggleView);

    statusTile = statusBar.addRightTile(item: _element.element, priority: 200);

    if (!isShowing()) {
      _element.element.style.display = 'none';
    }

    _handleLaunchesChanged();
  }

  void _handleLaunchesChanged([_]) {
    if (_element == null) return;

    List<Launch> launches = launchManager.launches;
    int count = launches.length;
    bool hasRunning = launches.any((l) => l.isRunning);

    if (count > 0) {
      if (!isShowing()) show();
      _badgeSpan.text =
          '${count} ${hasRunning ? 'running ' : ''} ${pluralize('process', count)}';
      _badgeSpan.toggleClass('badge-info', hasRunning);
    } else {
      hide();
      _badgeSpan.text = '';
    }
  }
}
