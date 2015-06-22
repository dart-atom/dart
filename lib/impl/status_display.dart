// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.status;

import 'dart:async';
import 'dart:html' show DivElement, Element, ImageElement, SpanElement;

import '../atom.dart';
import '../atom_statusbar.dart';
import '../elements.dart';
import '../jobs.dart';
import '../state.dart';
import '../utils.dart';

const Duration _shortDuration = const Duration(milliseconds: 400);

// TODO: Add a close box on the jobs dialog.

class StatusDisplay implements Disposable {
  final Disposables _disposables = new Disposables();
  StreamSubscription _subscription;

  Tile _statusbarTile;
  Timer _timer;

  Panel _jobsPanel;
  DivElement _jobsPanelElement;

  StatusDisplay(StatusBar statusBar) {
    CoreElement statusElement = new CoreElement.div()
        ..inlineBlock()..clazz('job-status-bar');
        statusElement.onClick.listen((_) => _showJobsDialog());
    _statusbarTile = statusBar.addRightTile(
        item: statusElement.element, priority: 10000);

    CoreElement spinner = new CoreElement('img')
        ..inlineBlockTight()
        ..clazz('status-spinner')
        ..setAttribute('src', 'atom://dart-lang-experimental/images/gear.svg');
    statusElement.add(spinner);

    CoreElement textLabel = new CoreElement.div()..inlineBlockTight()
        ..clazz('text-label')..clazz('text-highlight');
    statusElement.add(textLabel);

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
        statusElement.toggleClass('showing', true);
      } else {
        _timer = new Timer(_shortDuration, () {
          textLabel.text = '';
          statusElement.toggleClass('showing', false);
        });
      }

      textLabel.toggleClass('showing', showing);
      spinner.toggleClass('showing', showing);

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
    _jobsPanelElement = new DivElement();
    _jobsPanelElement.classes.add('jobs-dialog');

    DivElement title = new DivElement()..classes.add('jobs-title');
    _jobsPanelElement.children.add(title);

    DivElement div = new DivElement()..classes.add('select-list');
    _jobsPanelElement.children.add(div);
    Element ol = new Element.ol()..classes.add('list-group');
    div.children.add(ol);

    _jobsPanel = atom.workspace.addModalPanel(item: _jobsPanelElement, visible: false);
    _jobsPanel.onDidDestroy.listen((_) {
      _jobsPanel = null;
    });
  }

  void _showJobsDialog() {
    _jobsPanel.show();
    _updateJobsDialog();
  }

  void _updateJobsDialog() {
    if (_jobsPanel == null || _jobsPanelElement == null) return;

    Element title = _jobsPanelElement.querySelector('div.jobs-title');
    title.text = jobs.allJobs.isEmpty ? 'No running jobs.' : '';

    Element ol = _jobsPanelElement.querySelector('div ol');
    ol.children.clear();

    for (JobInstance jobInstance in jobs.allJobs) {
      Job job = jobInstance.job;

      CoreElement item = new CoreElement.li()..layoutHorizontal()..clazz('job-container');
      CoreElement title = item.add(new CoreElement.div()..inlineBlock()..flex());
      title.text = jobInstance.isRunning ? '${job.name}…' : job.name;

      if (jobInstance.isRunning) {
        CoreElement block = item.add(
            new CoreElement.div()..inlineBlock()..clazz('jobs-progress'));
        block.add(new ProgressElement());
      }

      if (job.infoAction != null) {
        CoreElement info = item.add(new CoreElement.div()
            ..inlineBlock()..clazz('info')..clazz('icon')..clazz('icon-question'));
        info.onClick.listen((_) => job.infoAction());
      }

      ol.children.add(item.element);
    }
  }
}
