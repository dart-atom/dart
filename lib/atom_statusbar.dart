// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// See the `status-bar` API [here](https://github.com/atom/status-bar).
library atom.statusbar;

import 'dart:js';

import 'package:atom/src/js.dart';

/// A wrapper around the `status-bar` API.
class StatusBar extends ProxyHolder {
  StatusBar(JsObject obj) : super(obj);

  /// Add a tile to the left side of the status bar. Lower priority tiles are
  /// placed further to the left. The [item] parameter to these methods can be a
  /// DOM element, a jQuery object, or a model object for which a view provider
  /// has been registered in the the view registry.
  Tile addLeftTile({dynamic item, int priority}) {
    Map m = {'item': item};
    if (priority != null) m['priority'] = priority;
    return new Tile(invoke('addLeftTile', m));
  }

  /// Add a tile to the right side of the status bar. Lower priority tiles are
  /// placed further to the right. The [item] parameter to these methods can be
  /// a DOM element, a jQuery object, or a model object for which a view
  /// provider has been registered in the the view registry.
  Tile addRightTile({dynamic item, int priority}) {
    Map m = {'item': item};
    if (priority != null) m['priority'] = priority;
    return new Tile(invoke('addRightTile', m));
  }

  /// Retrieve all of the tiles on the left side of the status bar.
  List<Tile> getLeftTiles() => new List.from(invoke('getLeftTiles').map((t) => new Tile(t)));

  /// Retrieve all of the tiles on the right side of the status bar.
  List<Tile> getRightTiles() => new List.from(invoke('getRightTiles').map((t) => new Tile(t)));
}

class Tile extends ProxyHolder {
  Tile(JsObject obj) : super(obj);

  /// Retrieve the priority that was assigned to the Tile when it was created.
  int getPriority() => invoke('getPriority');

  /// Retrieve the Tile's item.
  dynamic getItem() => invoke('getItem');

  /// Remove the Tile from the status bar.
  void destroy() => invoke('destroy');
}
