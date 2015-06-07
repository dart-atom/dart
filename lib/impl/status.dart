// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.status;

import 'dart:async';
import 'dart:html' show DivElement, SpanElement;

import '../atom_statusbar.dart';
import '../jobs.dart';
import '../state.dart';
import '../utils.dart';

class StatusDisplay implements Disposable {
  Tile _tile;
  StreamSubscription _subscription;

  StatusDisplay(StatusBar statusBar) {
    DivElement element = new DivElement();
    element.classes.add('inline-block');
    _tile = statusBar.addRightTile(item: element, priority: 10000);

    SpanElement span = new SpanElement();
    span.classes.add('inline-block');
    element.children.add(span);

    _subscription = jobs.onJobChanged.listen((Job job) {
      String title = job == null ? '' : '${job.name}…';
      span.text = title;
    });

    // SpanElement spinner = new SpanElement();
    // spinner.classes.addAll(['loading', 'loading-spinner-tiny', 'inline-block']);
    // element.children.add(spinner);
  }

  void dispose() {
    _subscription.cancel();
    _tile.destroy();
  }
}
