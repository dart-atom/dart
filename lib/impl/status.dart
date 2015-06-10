// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.status;

import 'dart:async';
import 'dart:html' show DivElement, Element, ImageElement, SpanElement;

import '../atom.dart';
import '../atom_statusbar.dart';
import '../jobs.dart';
import '../state.dart';
import '../utils.dart';

const Duration _shortDuration = const Duration(milliseconds: 400);

class StatusDisplay implements Disposable {
  StreamSubscription _subscription;
  Tile _statusbarTile;
  Panel _jobsPanel;
  Timer _timer;
  Disposables _disposables = new Disposables();
  DivElement _element;

  StatusDisplay(StatusBar statusBar) {
    DivElement element = new DivElement();
    element.classes.addAll(['inline-block', 'job-status-bar']);
    element.onClick.listen((_) => _showJobsDialog());
    _statusbarTile = statusBar.addRightTile(item: element, priority: 10000);

    ImageElement spinner = new ImageElement();
    spinner.src = 'atom://dart-lang/images/gear.svg';
    spinner.classes.addAll(['inline-block-tight', 'status-spinner']);
    element.children.add(spinner);

    DivElement textLabel = new DivElement();
    textLabel.classes.addAll(['inline-block-tight', 'text-label', 'text-highlight']);
    element.children.add(textLabel);

    _createJobsPanel();

    _subscription = jobs.onJobChanged.listen((_) {
      Job job = jobs.activeJob;
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

      _updateJobsDialog();
    });

    _disposables.add(atom.commands.add('atom-text-editor', 'core:cancel', (_) {
      if (_jobsPanel != null) _jobsPanel.hide();
    }));

    _disposables.add(atom.commands.add(
      'atom-workspace', 'dart-lang:show-jobs', (_) => _showJobsDialog()));
  }

  void dispose() {
    _subscription.cancel();
    _statusbarTile.destroy();
    _disposables.dispose();
    if (_jobsPanel != null) _jobsPanel.destroy();
  }

  void _createJobsPanel() {
    _element = new DivElement();
    _element.classes.add('jobs-dialog');

    DivElement title = new DivElement()..classes.add('jobs-title');
    _element.children.add(title);

    DivElement div = new DivElement()..classes.add('select-list');
    _element.children.add(div);
    Element ol = new Element.ol()..classes.add('list-group');
    div.children.add(ol);

    _jobsPanel = atom.workspace.addModalPanel(item: _element, visible: false);
    _jobsPanel.onDidDestroy.listen((_) {
      _jobsPanel = null;
    });
  }

  void _showJobsDialog() {
    _jobsPanel.show();
    _updateJobsDialog();
  }

  void _updateJobsDialog() {
    if (_jobsPanel == null || _element == null) return;

    Element title = _element.querySelector('div.jobs-title');
    title.text = jobs.allJobs.isEmpty ? 'No running jobs.' : '';

    Element ol = _element.querySelector('div ol');
    ol.children.clear();

    for (JobInstance jobInstance in jobs.allJobs) {
      Job job = jobInstance.job;

      Element item = new Element.li()
          ..setAttribute('layout', '')..setAttribute('horizontal', '');
      DivElement title = new DivElement()
          ..classes.add('inline-block')..setAttribute('flex', '');
      title.text = jobInstance.isRunning ? '${job.name}…' : job.name;
      item.children.add(title);

      if (jobInstance.isRunning) {
        DivElement block = new DivElement()..classes.addAll(['inline-block', 'jobs-progress']);
        item.children.add(block);

        Element progress = new Element.tag('progress')..classes.add('inline-block');
        block.children.add(progress);
        SpanElement span = new SpanElement()..classes.add('inline-block');
        block.children.add(span);
      }

      ol.children.add(item);
    }
  }
}
