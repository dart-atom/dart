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

import 'atom.dart';
import 'state.dart';

/**
 * An abstract representation of a long running task.
 */
abstract class Job {
  final String name;

  Job(this.name);

  /// Schedule the [Job] for execution.
  void schedule() => jobs.schedule(this);

  Future run();

  String toString() => name;
}

class JobManager {
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

  void _enqueue(Job job) {
    JobInstance instance = new JobInstance(this, job);
    _jobs.add(instance);

    // TODO: We need a more sophisticated algorithim.
    _exec(instance);
  }

  void _exec(JobInstance job) {
    job._running = true;

    // TODO: fire event
    print('starting job "${job.name}"');
    _toasts.addInfo('${job.name} started.');

    Future f = job.job.run();
    f.then((_) {
      // TODO: We don't want to use notifications for job completion going forward.
      _toasts.addSuccess('${job.name} completed.');
    }).whenComplete(() {
      _complete(job);
    }).catchError((e) {
      _toasts.addError('${job.name} failed.', options: {'detail': '${e}'});
    });
  }

  void _complete(JobInstance job) {
    job._running = false;
    _jobs.remove(job);

    // TODO: fire event
    print('finished job "${job.name}"');
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
