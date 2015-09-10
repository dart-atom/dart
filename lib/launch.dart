/// A library to manage launching application.
library atom.launch;

import 'dart:async';

import 'atom.dart';
import 'utils.dart';

class LaunchManager implements Disposable {
  StreamController<Launch> _launchAdded = new StreamController.broadcast(sync: true);
  StreamController<Launch> _launchActivated = new StreamController.broadcast();
  StreamController<Launch> _launchTerminated = new StreamController.broadcast();
  StreamController<Launch> _launchRemoved = new StreamController.broadcast();

  Launch _activeLaunch;
  final List<Launch> _launches = [];

  LaunchManager();

  Launch get activeLaunch => _activeLaunch;

  List<Launch> get launches => _launches;

  void addLaunch(Launch launch) {
    _launches.add(launch);
    bool activated = false;

    // Automatically remove all dead launches.
    List removed = [];
    _launches.removeWhere((l) {
      if (l.isTerminated) {
        if (_activeLaunch == l) _activeLaunch = null;
        removed.add(l);
      }
      return l.isTerminated;
    });

    if (_activeLaunch == null) {
      _activeLaunch = launch;
      activated = true;
    }

    removed.forEach((l) => _launchRemoved.add(l));
    _launchAdded.add(launch);
    if (activated) _launchActivated.add(launch);
  }

  void removeLaunch(Launch launch) {
    _launches.remove(launch);
    bool activeChanged = false;
    if (launch == _activeLaunch) {
      _activeLaunch = null;
      if (_launches.isNotEmpty) _activeLaunch = launches.first;
      activeChanged = true;
    }

    _launchRemoved.add(launch);
    if (activeChanged) _launchActivated.add(_activeLaunch);
  }

  void setActiveLaunch(Launch launch) {
    if (launch != _activeLaunch) {
      _activeLaunch = launch;
      _launchActivated.add(_activeLaunch);
    }
  }

  Stream<Launch> get onLaunchAdded => _launchAdded.stream;
  Stream<Launch> get onLaunchActivated => _launchActivated.stream;
  Stream<Launch> get onLaunchTerminated => _launchTerminated.stream;
  Stream<Launch> get onLaunchRemoved => _launchRemoved.stream;

  void dispose() {
    for (Launch launch in _launches.toList()) {
      launch.dispose();
    }
  }
}

class LaunchType {
  static const CLI = 'cli';
  static const SHELL = 'shell';
  static const SKY = 'sky';
  static const WEB = 'web';

  final String type;

  LaunchType(this.type);

  operator== (obj) => obj is LaunchType && obj.type == type;

  int get hashCode => type.hashCode;

  String toString() => type;
}

class Launch implements Disposable {
  static int _id = 0;

  final LaunchType launchType;
  final String title;
  final LaunchManager manager;
  final int id = ++_id;
  final Function killHandler;

  int servicePort;

  StreamController<String> _stdout = new StreamController.broadcast();
  StreamController<String> _stderr = new StreamController.broadcast();

  int _exitCode;

  Launch(this.launchType, this.title, this.manager, {this.killHandler});

  int get exitCode => _exitCode;
  bool get errored => _exitCode != null && _exitCode != 0;

  bool get isRunning => _exitCode == null;
  bool get isTerminated => _exitCode != null;

  bool get isActive => manager.activeLaunch == this;

  Stream<String> get onStdout => _stdout.stream;
  Stream<String> get onStderr => _stderr.stream;

  void pipeStdout(String str) => _stdout.add(str);
  void pipeStderr(String str) => _stderr.add(str);

  bool canDebug() => isRunning && servicePort != null;

  bool canKill() => killHandler != null;

  Future kill() {
    if (killHandler != null) {
      var f = killHandler();
      return f is Future ? f : new Future.value();
    } else {
      return new Future.value();
    }
  }

  void launchTerminated(int exitCode) {
    if (_exitCode != null) return;
    _exitCode = exitCode;

    if (errored) {
      atom.notifications.addError('${this} exited with error code ${exitCode}.');
    } else {
      atom.notifications.addSuccess('${this} finished.');
    }

    manager._launchTerminated.add(this);
  }

  void dispose() {
    if (canKill() && !isRunning) {
      kill();
    }
  }

  String toString() => '${launchType}-${id}: ${title}';
}
