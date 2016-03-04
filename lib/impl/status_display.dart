// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.status;

import 'dart:async';

import 'package:atom/utils/disposable.dart';

import '../atom.dart';
import '../atom_statusbar.dart';
import '../elements.dart';
import '../jobs.dart';
import '../state.dart';
import '../utils.dart';

// TODO: De-bounce the jobs display by 100ms.

const Duration _shortDuration = const Duration(milliseconds: 400);

class StatusDisplay implements Disposable {
  final Disposables _disposables = new Disposables();
  StreamSubscription _subscription;

  JobsDialog dialog;

  Tile _statusbarTile;

  Timer _timer;

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

      int jobLen = jobs.allJobs.length;
      countBadge.text = jobLen == 0 ? '' : '${jobLen} ${pluralize('job', jobLen)}';

      spinner.toggleClass('showing', showing);
      textLabel.toggleClass('showing', showing);
      countBadge.toggleClass('showing', jobLen > 1);

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
    dialog = new TitledModelDialog('', classes: 'jobs-dialog');
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

      CoreElement item = li(c: 'job-container')
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
