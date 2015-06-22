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

// TODO: We're sending a few more events from here than we need to.

/**
 * An abstract representation of a long running task.
 */
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
  void schedule() => jobs.schedule(this);

  Future run();

  String toString() => name;
}

class JobManager {
  StreamController<Job> _controller = new StreamController.broadcast();
  List<JobInstance> _jobs = [];
  NotificationManager _toasts;

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

  void schedule(Job job) => _enqueue(job);

  Stream<Job> get onJobChanged => _controller.stream;

  void _enqueue(Job job) {
    _logger.fine('scheduling job ${job.name}');
    _jobs.add(new JobInstance(this, job));
    _checkForRunnableJobs();
    _controller.add(activeJob);
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
    _controller.add(activeJob);

    job.run().then((result) {
      if (!job.quiet) {
        _toasts.addSuccess('${jobInstance.name} completed.',
            detail: result is String ? result : null,
            dismissable: result != null && job.pinResult);
      }
    }).whenComplete(() {
      _complete(jobInstance);
    }).catchError((e) {
      _toasts.addError('${job.name} failed.', detail: '${e}', dismissable: true);
    });
  }

  void _complete(JobInstance job) {
    _logger.fine('finished job ${job.name}');
    job._running = false;
    _jobs.remove(job);
    _checkForRunnableJobs();
    if (activeJob == null) _controller.add(null);
  }
}

class JobInstance {
  final JobManager jobs;
  final Job job;
  bool _running = false;

  JobInstance(this.jobs, this.job);

  String get name => job.name;
  bool get isRunning => _running;
}
