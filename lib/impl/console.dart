library atom.console;

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

// TODO: hide when last running launch terminates (w/o error?)

// TODO: auto show when a launch starts, if set in the prefs

class ConsoleView extends AtomView {
  CoreElement body;
  CoreElement title;

  ConsoleView() : super('Console', classes: 'console-view dartlang', prefName: 'Console',
      rightPanel: false, cancelCloses: false, showTitle: false) {
    root.toggleClass('tree-view', false);

    // TODO: show a close button

    content.add([
      body = div(),
      title = div(c: 'console-title-area')
    ]);

    // TODO: listen for launch changes

    // TODO: track launch output

    // TODO: auto-open on launch? on launch with console output?

    subs.add(launchManager.onLaunchAdded.listen(_launchAdded));
    subs.add(launchManager.onChangedActiveLaunch.listen(_changedActiveLaunch));
    subs.add(launchManager.onLaunchChanged.listen((_) => _buildTitle()));
    subs.add(launchManager.onLaunchRemoved.listen(_launchRemoved));
  }

  void _launchAdded(Launch launch) {
    // TODO:
    _buildTitle();
  }

  void _changedActiveLaunch(Launch launch) {
    // TODO:
    _buildTitle();
  }

  void _launchRemoved(Launch launch) {
    // TODO:
    _buildTitle();
  }

  // TODO: subtitle of debug | clear | kill

  void _buildTitle() {
    // TODO: close button somewhere

    title.clear();

    for (Launch launch in launchManager.launches) {
      CoreElement badge = span(c: 'badge');
      if (launch.isActive) badge.toggleClass('badge-info');

      if (launch.isRunning) {
        badge.text = launch.title;
      } else {
        badge.toggleClass('launch-terminated');
        badge.text = '${launch.title} [0]'; // TODO: use a real exit code
      }

      badge.click(() => launch.manager.setActiveLaunch(launch));
      title.add(badge);
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
