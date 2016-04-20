import 'dart:js';

import 'package:atom/atom.dart';

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
