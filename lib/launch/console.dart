
/// A console output view.
library atom.console;

import 'dart:html' show ScrollAlignment;

import '../atom.dart';
import '../atom_statusbar.dart';
import '../elements.dart';
import '../impl/errors.dart';
import '../state.dart';
import '../utils.dart';
import '../views.dart';
import 'launch.dart';

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
    ViewGroup group = viewGroupManager.getGroup('bottom');
    if (group.views.length == 1 && group.hasViewId(errorViewId)) {
      _errorsView = group.getViewById(errorViewId);
      group.removeView(_errorsView);
    }

    ConsoleView2 view = new ConsoleView2(this, launch);
    _allViews.add(view);
    viewGroupManager.addView('bottom', view);
  }

  void _launchRemoved(Launch launch) {
    // Re-show the errors view if we auto-hide it.
    if (_errorsView != null && launchManager.launches.isEmpty) {
      if (!viewGroupManager.hasViewId(errorViewId)) {
        viewGroupManager.addView('bottom', _errorsView);
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
        viewGroupManager.addView('bottom', view);
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

// TODO: activity spinner - where to show?

class ConsoleView2 extends View {
  // Only show a set amount of lines of output.
  static const _maxLines = 200;

  static int _idCount = 0;

  final ConsoleController controller;
  final Launch launch;

  int _launchId;
  StreamSubscriptions _subs = new StreamSubscriptions();

  CoreElement element;
  CoreElement output;
  String _lastText = '';

  CoreElement _debugButton;
  CoreElement _terminateButton;

  ConsoleView2(this.controller, this.launch) {
    _launchId = _idCount++;

    CoreElement buttons;

    element = div(c: 'console-view')..add([
      buttons = div(c: 'button-bar btn-group btn-group-sm')..layoutHorizontal(),
      output = new CoreElement('pre', classes: 'console-line')
    ]);

    _subs.add(launchManager.onLaunchActivated.listen(_launchActivated));
    _subs.add(launchManager.onLaunchTerminated.listen(_launchTerminated));
    _subs.add(launchManager.onLaunchRemoved.listen(_launchRemoved));

    element.listenForUserCopy();

    // Allow the text in the console to be selected.
    output.element.tabIndex = -1;

    _subs.add(launch.onStdio.listen((text) => _emitText(
        text.text, error: text.error, subtle: text.subtle, highlight: text.highlight)));

    // debug
    // TODO: Listen for obs. port being provided after a delay.
    if (launch.canDebug()) {
      _debugButton = buttons.add(
        button(text: 'Observatory', c: 'btn icon icon-dashboard')
      );
      _debugButton.tooltip = 'Open the Observatory';
      _debugButton.click(() {
        shell.openExternal('http://localhost:${launch.servicePort}/');
      });
    }

    // kill
    if (launch.canKill()) {
      _terminateButton = buttons.add(
        button(text: 'Terminate', c: 'btn icon icon-primitive-square')
      );
      _terminateButton.tooltip = 'Terminate process';
      _terminateButton.click(() => launch.kill());
    }
  }

  String get label => launch.launchConfiguration.shortResourceName;

  String get id => 'console.${_launchId}';

  void _launchActivated(Launch l) {
    if (launch == l) {
      if (viewGroupManager.hasViewId(id)) {
        viewGroupManager.activate(this);
      } else {
        viewGroupManager.addView('bottom', this);
      }
    }
  }

  void _launchTerminated(Launch l) {
    if (launch == l) {
      tabElement.toggleClass('launch-terminated');
      if (!_lastText.endsWith('\n')) _emitText('\n');
      _emitText('• exited with code ${launch.exitCode} •', highlight: true);
      _debugButton?.disabled = true;
      _terminateButton?.disabled = true;
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

  // ' (dart:core-patch/errors_patch.dart:27)'
  // ' (packages/flutter/src/rendering/flex.dart:475)'
  // ' (/Users/foo/flutter/flutter_playground/lib/main.dart:6)'
  // ' (file:///Users/foo/flutter/flutter_playground/lib/main.dart:6)'
  // ' (http:localhost:8080/src/errors.dart:27)'
  // ' (http:localhost:8080/src/errors.dart:27:12)'
  // ' (file:///ssd2/sky/engine/src/out/android_Release/gen/sky/bindings/Customhooks.dart:35)'
  //
  // 'test/utils_test.dart 21 '
  // 'test/utils_test.dart 21:7 '
  final RegExp _consoleMatcher =
      new RegExp(r' \((\S+\.dart):(\d+)(:\d+)?\)|(\S+\.dart) (\d+)(:\d+)? ');

  void _emitText(String str, {bool error: false, bool subtle: false, bool highlight: false}) {
    _lastText = str;

    List<Match> matches = _consoleMatcher.allMatches(str).toList();

    CoreElement e;

    if (matches.isEmpty) {
      e = span(text: str);
    } else {
      e = span();

      int offset = 0;

      for (Match match in matches) {
        String ref = match.group(1) ?? match.group(4);
        String line = match.group(2) ?? match.group(5);
        int startIndex = match.start + (match.group(1) != null ? 2 : 0);

        e.add(span(text: str.substring(offset, startIndex)));

        String text = '${ref}:${line}';
        CoreElement link = e.add(span(text: text));

        offset = startIndex + text.length;

        launch.resolve(ref).then((String path) {
          if (path != null) {
            link.toggleClass('trace-link');
            link.click(() {
              editorManager.jumpToLine(
                path,
                int.parse(line, onError: (_) => 1) - 1,
                selectLine: true
              );
            });
          }
        });
      }

      if (offset != str.length) {
        e.add(span(text: str.substring(offset)));
      }
    }

    if (highlight) e.toggleClass('text-highlight');
    if (error) e.toggleClass('console-error');
    if (subtle) e.toggleClass('text-subtle');

    output.add(e);

    List children = output.element.children;
    if (children.length > _maxLines) {
      children.remove(children.first);
    }

    if (output.element.parent != null) {
      output.element.scrollIntoView(ScrollAlignment.BOTTOM);
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
