library atom.treeview;

import 'dart:js';

import 'package:atom/src/js.dart';
import 'package:atom/utils/disposable.dart';

// TODO: Dispatch back to the original service?

abstract class FileIconsService implements Disposable {
  Function _onWillDeactivate;

  /// Returns a CSS class name to add to the file view
  String iconClassForPath(String path);

  /// An event that lets the tree view return to its default icon strategy.
  void onWillDeactivate(Function fn) {
    _onWillDeactivate = fn;
  }

  void dispose() {
    if (_onWillDeactivate != null) _onWillDeactivate();
  }

  JsObject toProxy() {
    return jsify(<String, dynamic>{
      'iconClassForPath': iconClassForPath,
      'onWillDeactivate': onWillDeactivate
    });
  }
}
