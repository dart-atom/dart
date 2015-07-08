// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.status;

import 'dart:async';

import '../atom.dart';
import '../atom_statusbar.dart';
import '../elements.dart';
import '../jobs.dart';
import '../state.dart';
import '../utils.dart';

const Duration _shortDuration = const Duration(milliseconds: 400);

// TODO: Add a close box on the jobs dialog.

// TODO: Move much of the code to a separate JobsDialog class

class StatusDisplay implements Disposable {
  final Disposables _disposables = new Disposables();
  StreamSubscription _subscription;

  Tile _statusbarTile;
  Timer _timer;

  Panel _jobsPanel;
  CoreElement _titleElement;
  CoreElement _listGroup;

  StatusDisplay(StatusBar statusBar) {
    CoreElement spinner;
    CoreElement textLabel;

    CoreElement statusElement = div(c: 'job-status-bar')
        ..inlineBlock()..click(_showJobsDialog)..add([
      spinner = img()..inlineBlockTight()..clazz('status-spinner')
          ..src = 'atom://dartlang/images/gear.svg',
      textLabel = div(c: 'text-label text-highlight')..inlineBlockTight()
    ]);

    _statusbarTile = statusBar.addRightTile(item: statusElement.element, priority: 1000);
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
      'atom-workspace', 'dartlang:show-jobs', (_) => _showJobsDialog()));
  }

  void dispose() {
    _subscription.cancel();
    _statusbarTile.destroy();
    _disposables.dispose();
    if (_jobsPanel != null) _jobsPanel.destroy();
  }

  void _createJobsPanel() {
    CoreElement panelElement = div(c: 'jobs-dialog')..add([
      _titleElement = div(c: 'jobs-title'),
      div(c: 'select-list')..add([
        _listGroup = ol(c: 'list-group')
      ])
    ]);

    _jobsPanel = atom.workspace.addModalPanel(item: panelElement.element, visible: false);
    _jobsPanel.onDidDestroy.listen((_) {
      _jobsPanel = null;
    });
  }

  void _showJobsDialog() {
    _jobsPanel.show();
    _updateJobsDialog();
  }

  void _updateJobsDialog() {
    if (_jobsPanel == null) return;

    _titleElement.text = jobs.allJobs.isEmpty ? 'No running jobs.' : '';
    _listGroup.element.children.clear();

    for (JobInstance jobInstance in jobs.allJobs) {
      Job job = jobInstance.job;

      CoreElement item = li(c: 'job-container')..layoutHorizontal()..add([
        div()..inlineBlock()..flex()
          ..text = jobInstance.isRunning ? '${job.name}…' : job.name
      ]);

      if (job.infoAction != null) {
        item.add([
          div(c: 'info')..inlineBlock()..icon('question')..click(job.infoAction)
        ]);
      }

      if (jobInstance.isRunning) {
        item.add([
          div(c: 'jobs-progress')..inlineBlock()..add([
            new ProgressElement()
          ])
        ]);
      }

      _listGroup.add(item);
    }
  }
}
