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

import 'package:atom/atom.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import 'state.dart';

final Logger _logger = new Logger('jobs');

typedef void VoidHandler();

/// An abstract representation of a long running task.
abstract class Job implements Disposable {
  final String name;
  final Object _schedulingRule;

  Job(this.name, [this._schedulingRule]);

  Object get schedulingRule => _schedulingRule;

  /// Don't show a notification on a successful completion.
  bool get quiet => false;

  /// Pin the notification after completion; the user will explicitly have to
  /// clear it.
  bool get pinResult => false;

  /// An action that when called will provide some additional information about
  /// the job.
  VoidHandler get infoAction => null;

  /// Schedule the [Job] for execution.
  Future<JobStatus> schedule() => jobs.schedule(this);

  Future run();

  bool get isCancellable => false;

  void cancel() => dispose();

  void dispose() { }

  String toString() => name;
}

enum Status {
  OK, ERROR
}

class JobStatus {
  static final JobStatus OK = new JobStatus(Status.OK);

  final Status status;
  final dynamic result;

  JobStatus(this.status, {this.result});
  JobStatus.ok(this.result) : status = Status.OK;
  JobStatus.error(this.result) : status = Status.ERROR;

  bool get isOk => status == Status.OK;
  bool get isError => status == Status.ERROR;

  String toString() => result == null ? status.toString() : '${status}: ${result}';
}

abstract class CancellableJob extends Job {
  Cancellable _cancellable;

  CancellableJob(String name, [Object schedulingRule]) : super(name, schedulingRule);

  bool get isCancellable => true;

  /// Subclasses must not override this method. See instead [doRun].
  Future run() {
    _cancellable = new Cancellable(doRun(), handleCancel);
    return _cancellable.cancellableFuture;
  }

  /// Perform the work that would normally be in [run] here.
  Future doRun();

  /// Invoked when this Job is cancelled.
  void handleCancel();

  void dispose() {
    if (_cancellable != null) _cancellable.cancel();
  }
}

class Cancellable {
  Future _future;
  Function _handleCancel;
  Completer _completer = new Completer();
  bool _wasCancelled = false;

  Cancellable(this._future, [this._handleCancel]) {
    _future.then((result) {
      if (!wasCancelled) _completer.complete(result);
    });
    _future.catchError((e) {
      if (!wasCancelled) _completer.completeError(e);
    });
  }

  Future get cancellableFuture => _completer.future;

  bool get wasCancelled => _wasCancelled;

  void cancel() {
    if (!wasCancelled) {
      _wasCancelled = true;

      if (!_completer.isCompleted) {
        if (_handleCancel != null) _handleCancel();
        // TODO: complete the completer?
        _completer.complete(null);
      }
    }
  }
}

class JobManager implements Disposable {
  StreamController<Job> _activeJobController = new StreamController.broadcast();
  StreamController<Job> _queueController = new StreamController.broadcast();
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

  Stream<Job> get onActiveJobChanged => _activeJobController.stream;
  Stream<Job> get onQueueChanged => _queueController.stream;

  Future<JobStatus> schedule(Job job) => _enqueue(job);

  void dispose() {
    List<JobInstance> list = new List.from(runningJobs);
    for (JobInstance job in list) {
      if (job.job.isCancellable) job.job.cancel();
    }
  }

  Future<JobStatus> _enqueue(Job job) {
    _logger.fine('scheduling job ${job.name}');
    JobInstance instance = new JobInstance(this, job);
    _jobs.add(instance);
    _checkForRunnableJobs();
    _checkNotifyJobChanged();
    _queueController.add(null);
    return instance.whenComplete;
  }

  void _checkForRunnableJobs() {
    Set rules = new Set();

    // Look for a rule that has no scheduling rule or that has one that does not
    // match any currently running rules.
    List<JobInstance> jobsCopy = new List.from(_jobs);
    for (JobInstance jobInstance in jobsCopy) {
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
    jobInstance.running = true;
    _checkNotifyJobChanged();

    new Future.sync(job.run).then((result) {
      if (!job.quiet) {
        String detail = result == null ? null : '${result}';
        _toasts.addSuccess('${jobInstance.name} completed.',
            detail: detail,
            dismissable: detail != null && detail.isNotEmpty && job.pinResult);
      }
      jobInstance._completer.complete(new JobStatus.ok(result));
    }).whenComplete(() {
      _complete(jobInstance);
    }).catchError((e) {
      jobInstance._completer.complete(new JobStatus.error(e));
      _toasts.addError('${job.name} failed.', description: '${e}', dismissable: true);
    });
  }

  void _complete(JobInstance job) {
    job.running = false;
    _logger.fine('finished job ${job.name} (${job.stopwatch.elapsedMilliseconds}ms)');
    _jobs.remove(job);
    _checkForRunnableJobs();
    _checkNotifyJobChanged();
    _queueController.add(null);
  }

  void _checkNotifyJobChanged() {
    Job current = activeJob;
    if (_lastNotifiedJob != current) {
      _activeJobController.add(current);
      _lastNotifiedJob = current;
    }
  }
}

class JobInstance {
  final JobManager jobs;
  final Job job;

  Completer<JobStatus> _completer = new Completer();
  Stopwatch stopwatch = new Stopwatch();
  bool _running = false;

  JobInstance(this.jobs, this.job);

  String get name => job.name;
  bool get isRunning => running;

  bool get running => _running;
  set running(bool value) {
    if (value) {
      stopwatch..reset()..start();
    } else {
      stopwatch..stop();
    }
    _running = value;
  }

  Future<JobStatus> get whenComplete => _completer.future;
}
