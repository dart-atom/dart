library atom.toolbar;

import 'dart:js';

import 'elements.dart';
import 'js.dart';
import 'state.dart';
import 'utils.dart';

// device-mobile

class ToolbarContribution implements Disposable {
  ToolbarTile _tile;

  ToolbarContribution(Toolbar toolbar) {
    CoreElement back;
    CoreElement forward;

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

    _tile = toolbar.addRightTile(item: e.element);
  }

  void dispose() => _tile.destroy();
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
      invoke('getLeftTiles').map((t) => new ToolbarTile(t)).toList();
  List<ToolbarTile> getRightTiles() =>
      invoke('getRightTiles').map((t) => new ToolbarTile(t)).toList();
}

class ToolbarTile extends ProxyHolder {
  ToolbarTile(JsObject obj) : super(obj);

  int getPriority() => invoke('getPriority');
  dynamic getItem() => invoke('getItem');
  void destroy() => invoke('destroy');
}
