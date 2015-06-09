// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.status;

import 'dart:async';
import 'dart:html' show DivElement, ImageElement;

import '../atom_statusbar.dart';
import '../jobs.dart';
import '../state.dart';
import '../utils.dart';

// TODO: On a click, open a progress view.

// TODO: Tooltip on hover.

const Duration _shortDuration = const Duration(milliseconds: 400);

class StatusDisplay implements Disposable {
  Tile _tile;
  StreamSubscription _subscription;
  Timer _timer;

  StatusDisplay(StatusBar statusBar) {
    DivElement element = new DivElement();
    element.classes.addAll(['inline-block', 'job-status-bar']);
    _tile = statusBar.addRightTile(item: element, priority: 10000);

    ImageElement spinner = new ImageElement();
    spinner.src = 'atom://dart-lang/images/gear.svg';
    spinner.classes.addAll(['inline-block-tight', 'status-spinner']);
    element.children.add(spinner);

    DivElement textLabel = new DivElement();
    textLabel.classes.addAll(['inline-block-tight', 'text-label', 'text-highlight']);
    element.children.add(textLabel);

    _subscription = jobs.onJobChanged.listen((Job job) {
      bool showing = job != null;

      if (_timer != null) {
        _timer.cancel();
        _timer = null;
      }

      if (job != null) {
        textLabel.text = '${job.name}…';
        element.classes.toggle('showing', true);
      } else {
        _timer = new Timer(_shortDuration, () {
          textLabel.text = '';
          element.classes.toggle('showing', false);
        });
      }

      textLabel.classes.toggle('showing', showing);
      spinner.classes.toggle('showing', showing);
    });
  }

  void dispose() {
    _subscription.cancel();
    _tile.destroy();
  }
}
