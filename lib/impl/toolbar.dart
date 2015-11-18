library atom.toolbar;

import 'dart:js';

import '../atom.dart';
import '../elements.dart';
import '../js.dart';
import '../state.dart';
import '../utils.dart';

// device-mobile

class ToolbarContribution implements Disposable {
  ToolbarTile leftTile;
  ToolbarTile rightTile;
  Disposable editorWatcher;

  CoreElement run;

  CoreElement back;
  CoreElement forward;

  ToolbarContribution(Toolbar toolbar) {
    leftTile = toolbar.addLeftTile(item: _buildLeftTile().element);
    rightTile = toolbar.addRightTile(item: _buildRightTile().element);
  }

  CoreElement _buildLeftTile() {
    CoreElement e = div(c: 'btn-group btn-group-sm dartlang-toolbar')..add([
      run = button(c: 'btn icon icon-playback-play')
    ]);

    run.click(() {
      TextEditor editor = atom.workspace.getActiveTextEditor();

      if (editor == null) {
        atom.notifications.addWarning('No active text editor.');
        return;
      }

      atom.commands.dispatch(atom.views.getView(editor), 'dartlang:run-application');
    });

    editorWatcher = atom.workspace.observeActivePaneItem((_) {
      run.enabled = atom.workspace.getActiveTextEditor() != null;
    });

    return e;
  }

  CoreElement _buildRightTile() {
    // <kbd class='key-binding'>⌘⌥A</kbd>
    CoreElement e = div(c: 'btn-group btn-group-sm dartlang-toolbar')..add([
      back = button(c: 'btn icon icon-arrow-left'),
      forward = button(c: 'btn icon icon-arrow-right')
    ]);

    back.disabled = true;
    back.click(() => navigationManager.goBack());
    forward.disabled = true;
    forward.click(() => navigationManager.goForward());

    navigationManager.onNavigate.listen((_) {
      back.disabled = !navigationManager.canGoBack();
      forward.disabled = !navigationManager.canGoForward();
    });

    return e;
  }

  void dispose() {
    leftTile.destroy();
    rightTile.destroy();
    editorWatcher.dispose();
  }
}

/// A wrapper around the `toolbar` API.
class Toolbar extends ProxyHolder {
  Toolbar(JsObject obj) : super(obj);

  ToolbarTile addLeftTile({dynamic item, int priority}) {
    Map m = {'item': item};
    if (priority != null) m['priority'] = priority;
    return new ToolbarTile(invoke('addLeftTile', m));
  }

  ToolbarTile addRightTile({dynamic item, int priority}) {
    Map m = {'item': item};
    if (priority != null) m['priority'] = priority;
    return new ToolbarTile(invoke('addRightTile', m));
  }

  List<ToolbarTile> getLeftTiles() =>
      new List.from(invoke('getLeftTiles').map((t) => new ToolbarTile(t)));

  List<ToolbarTile> getRightTiles() =>
      new List.from(invoke('getRightTiles').map((t) => new ToolbarTile(t)));
}

class ToolbarTile extends ProxyHolder {
  ToolbarTile(JsObject obj) : super(obj);

  int getPriority() => invoke('getPriority');
  dynamic getItem() => invoke('getItem');
  void destroy() => invoke('destroy');
}
