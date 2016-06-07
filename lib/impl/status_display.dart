// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.status;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';

import '../atom_statusbar.dart';
import '../elements.dart';
import '../jobs.dart';
import '../state.dart';

const Duration _showDelay = const Duration(milliseconds: 200);

const Duration _hideDelay = const Duration(milliseconds: 400);

class StatusDisplay implements Disposable {
  final Disposables _disposables = new Disposables();
  StreamSubscription _subscription;

  JobsDialog dialog;

  Tile _statusbarTile;

  Timer _showTimer;
  Timer _hideTimer;

  StatusDisplay(StatusBar statusBar) {
    CoreElement spinner;
    CoreElement textLabel;
    CoreElement countBadge;

    CoreElement statusElement = div(c: 'job-status-bar dartlang')
      ..inlineBlock()
      ..click(_showJobsDialog)
      ..add([
        spinner = img()
          ..inlineBlockTight()
          ..clazz('status-spinner')
          ..src = 'atom://dartlang/images/gear.svg',
        textLabel = div(c: 'text-label')..inlineBlockTight(), // text-highlight
        countBadge = span(c: 'badge badge-info badge-count')
      ]);

    _statusbarTile =
        statusBar.addRightTile(item: statusElement.element, priority: 1000);

    _subscription = jobs.onQueueChanged.listen((_) {
      Job job = jobs.activeJob;

      bool shouldShow = job != null;
      bool isShowing = statusElement.element.classes.contains('showing');

      if (shouldShow && !isShowing) {
        _hideTimer?.cancel();
        _hideTimer = null;

        // Show it.
        if (_showTimer == null) {
          _showTimer = new Timer(_showDelay, () {
            statusElement.toggleClass('showing', true);
            _showTimer = null;
          });
        }
      } else if (!shouldShow && isShowing) {
        _showTimer?.cancel();
        _showTimer = null;

        // Hide it.
        if (_hideTimer == null) {
          _hideTimer = new Timer(_hideDelay, () {
            textLabel.text = '';
            statusElement.toggleClass('showing', false);
            _hideTimer = null;
          });
        }
      }

      if (job != null) {
        textLabel.text = '${job.name}…';
      }

      int jobsLength = jobs.allJobs.length;
      countBadge.text = jobsLength == 0 ? '' : '${jobsLength} ${pluralize('job', jobsLength)}';

      spinner.toggleClass('showing', shouldShow);
      textLabel.toggleClass('showing', shouldShow);
      countBadge.toggleClass('showing', jobsLength > 1);

      _updateJobsDialog();
    });

    _disposables.add(atom.commands.add(
        'atom-workspace', 'dartlang:show-jobs', (_) => _showJobsDialog()));
  }

  void dispose() {
    _subscription.cancel();
    _statusbarTile.destroy();
    _disposables.dispose();
  }

  void _showJobsDialog() {
    if (dialog == null) {
      dialog = new JobsDialog();
      _disposables.add(dialog);
    }
    dialog.show();
    dialog.updateJobsDialog();
  }

  void _updateJobsDialog() {
    if (dialog != null) dialog.updateJobsDialog();
  }
}

class JobsDialog implements Disposable {
  TitledModelDialog dialog;
  CoreElement _listGroup;

  JobsDialog() {
    dialog = new TitledModelDialog('', classes: 'list-dialog');
    dialog.content.add([
      div(c: 'select-list')..add([_listGroup = ol(c: 'list-group')])
    ]);
  }

  void show() => dialog.show();

  void updateJobsDialog() {
    dialog.title.text = jobs.allJobs.isEmpty ?
       'No running jobs.' :
       '${jobs.allJobs.length} running ${pluralize('job', jobs.allJobs.length)}';
    _listGroup.element.children.clear();

    for (JobInstance jobInstance in jobs.allJobs) {
      Job job = jobInstance.job;

      CoreElement item = li(c: 'item-container')
        ..layoutHorizontal()
        ..add([
          div()
            ..inlineBlock()
            ..flex()
            ..text = jobInstance.isRunning ? '${job.name}…' : job.name
        ]);

      if (job.infoAction != null) {
        item.add([
          div(c: 'info')
            ..inlineBlock()
            ..icon('question')
            ..click(job.infoAction)
        ]);
      }

      if (jobInstance.isRunning) {
        item.add([
          div(c: 'jobs-progress')
            ..inlineBlock()
            ..add([new ProgressElement()])
        ]);
      }

      _listGroup.add(item);
    }
  }

  void dispose() => dialog.dispose();
}
