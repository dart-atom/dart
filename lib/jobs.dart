// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * A library to manage long running tasks. Create instances of [Job] for long
 * running tasks. Use a [JobManager] to track tasks that are running.
 *
 *     MyFooJob job = new MyFooJob(baz);
 *     job.schedule();
 */
library atom.jobs;

import 'dart:async';

import 'package:logging/logging.dart';

import 'atom.dart';
import 'state.dart';

final Logger _logger = new Logger('jobs');

/// An abstract representation of a long running task.
abstract class Job {
  final String name;
  final Object schedulingRule;

  Job(this.name, [this.schedulingRule]);

  /// Don't show a notification on a successful completion.
  bool get quiet => false;

  /// Pin the notification after completion; the user will explicitly have to
  /// clear it.
  bool get pinResult => false;

  /// An action that when called will provide some additional information about
  /// the job.
  Function get infoAction => null;

  /// Schedule the [Job] for execution.
  Future schedule() => jobs.schedule(this);

  Future run();

  String toString() => name;
}

class JobManager {
  StreamController<Job> _controller = new StreamController.broadcast();
  List<JobInstance> _jobs = [];
  NotificationManager _toasts;
  Job _lastNotifiedJob = null;

  JobManager() {
    _toasts = atom.notifications;
  }

  /// Return the active [Job]. This can return `null` if there is no currently
  /// executing job.
  Job get activeJob {
    JobInstance instance = _jobs.firstWhere((j) => j.isRunning, orElse: () => null);
    return instance == null ? null : instance.job;
  }

  List<JobInstance> get runningJobs => _jobs.where((j) => j.isRunning).toList();

  List<JobInstance> get allJobs => _jobs.toList();

  Stream<Job> get onJobChanged => _controller.stream;

  Future schedule(Job job) => _enqueue(job);

  Future _enqueue(Job job) {
    _logger.fine('scheduling job ${job.name}');
    JobInstance instance = new JobInstance(this, job);
    _jobs.add(instance);
    _checkForRunnableJobs();
    _checkNotifyJobChanged();
    return instance.whenComplete;
  }

  void _checkForRunnableJobs() {
    Set rules = new Set();

    // Look for a rule that has no scheduling rule or that has one that does not
    // match any currently running rules.
    for (JobInstance jobInstance in _jobs) {
      if (jobInstance.isRunning) {
        rules.add(jobInstance.job.schedulingRule);
      } else {
        Object rule = jobInstance.job.schedulingRule;
        if (rule == null || !rules.contains(rule)) {
          rules.add(rule);
          _exec(jobInstance);
        }
      }
    }
  }

  void _exec(JobInstance jobInstance) {
    Job job = jobInstance.job;

    _logger.fine('starting job ${job.name}');
    jobInstance._running = true;
    _checkNotifyJobChanged();

    job.run().then((result) {
      if (!job.quiet) {
        String detail = result == null ? null : '${result}';
        _toasts.addSuccess('${jobInstance.name} completed.',
            detail: detail,
            dismissable: detail != null && detail.isNotEmpty && job.pinResult);
      }
      jobInstance._completer.complete(result);
    }).whenComplete(() {
      _complete(jobInstance);
    }).catchError((e) {
      jobInstance._completer.complete();
      _toasts.addError('${job.name} failed.', detail: '${e}', dismissable: true);
    });
  }

  void _complete(JobInstance job) {
    _logger.fine('finished job ${job.name}');
    job._running = false;
    _jobs.remove(job);
    _checkForRunnableJobs();
    _checkNotifyJobChanged();
  }

  void _checkNotifyJobChanged() {
    Job current = activeJob;
    if (_lastNotifiedJob != current) {
      _controller.add(current);
      _lastNotifiedJob = current;
    }
  }
}

class JobInstance {
  final JobManager jobs;
  final Job job;

  Completer _completer = new Completer();
  bool _running = false;

  JobInstance(this.jobs, this.job);

  String get name => job.name;
  bool get isRunning => _running;

  Future get whenComplete => _completer.future;
}
