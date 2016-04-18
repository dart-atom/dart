
import 'dart:async';

import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';

import '../atom.dart';
import '../elements.dart';
import '../state.dart';
import '../views.dart';

final String _outlinePref = '${pluginId}.showOutlineView';

class OutlineController2 implements Disposable {
  Disposables disposables = new Disposables();
  StreamSubscription sub;

  OutlineView view;
  String _focusedPath;

  OutlineController2() {
    disposables.add(atom.commands.add(
        'atom-workspace', '${pluginId}:toggle-outline-view', (_) {
      if (view.isViewShowing() != atom.config.getValue(_outlinePref)) {
        _toggleShowing(!view.isViewShowing());
      } else {
        atom.config.setValue(_outlinePref, !view.isViewShowing());
      }
    }));

    view = new OutlineView();
    _toggleShowing(atom.config.getValue(_outlinePref));
    disposables.add(atom.workspace.observeActivePaneItem(_focusChanged));
    sub = atom.config.onDidChange(_outlinePref).listen(_toggleShowing);
  }

  void _toggleShowing(bool show) {
    if (show && !view.isViewShowing()) {
      viewGroupManager.addView('right', view);
    } else if (!show && view.isViewShowing()) {
      viewGroupManager.removeViewId(view.id);
    }
  }

  void _focusChanged(_) {
    TextEditor editor = atom.workspace.getActiveTextEditor();
    final String newFocus = editor?.getPath();

    if (newFocus != _focusedPath) {
      _focusedPath = newFocus;
      view.switchTo(_focusedPath);
    }
  }

  void dispose() {
    sub.cancel();
    disposables.dispose();
    view.dispose();
  }
}

class OutlineView extends View {
  CoreElement subtitle;

  OutlineView() {
    content.toggleClass('type-hierarchy');
    content.toggleClass('tab-scrollable-container');
    content.add([
      div(c: 'view-header view-header-static')..add([
        div(c: 'view-title')..text = 'Outline',
        subtitle = div(c: 'view-subtitle')
      ]),
      // treeBuilder = new ListTreeBuilder(_render)
    ]);
    // treeBuilder.toggleClass('tab-scrollable');
    // treeBuilder.onClickNode.listen(_jumpTo);
  }

  String get id => 'outlineView';

  String get label => 'Outline';

  bool isViewShowing() => viewGroupManager.hasViewId(id);

  void switchTo(String path) {
    subtitle.text = path == null ? ' ' : atom.project.relativizePath(path)[1];
    subtitle.tooltip = path == null ? '' : path;

    // TODO:

  }

  void dispose() {
    // TODO: implement dispose

  }
}

class OutlineViewPage {
  // TODO:

}
