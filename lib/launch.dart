/// A library to manage launching application.
library atom.launch;

import 'dart:async';

import 'utils.dart';

// TODO: launch type: sky, cli, web, shell, ...

class LaunchManager implements Disposable {
  StreamController<Launch> _launchAdded = new StreamController.broadcast();
  StreamController<Launch> _launchChanged = new StreamController.broadcast();
  StreamController<Launch> _launchRemoved = new StreamController.broadcast();

  StreamController<Launch> _changedActiveLaunch = new StreamController.broadcast();

  Launch _activeLaunch;
  final List<Launch> _launches = [];

  LaunchManager();

  Launch get activeLaunch => _activeLaunch;

  List<Launch> get launches => _launches;

  // TODO: automatically remove all dead launches?

  void addLaunch(Launch launch) {
    _launches.add(launch);
    bool activeChanged = false;
    if (_activeLaunch == null) {
      _activeLaunch = launch;
      activeChanged = true;
    }

    _launchAdded.add(launch);
    if (activeChanged) _changedActiveLaunch.add(launch);
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
    if (activeChanged) _changedActiveLaunch.add(_activeLaunch);
  }

  void setActiveLaunch(Launch launch) {
    if (launch != _activeLaunch) {
      _activeLaunch = launch;
      _changedActiveLaunch.add(_activeLaunch);
    }
  }

  Stream<Launch> get onLaunchAdded => _launchAdded.stream;
  Stream<Launch> get onLaunchChanged => _launchChanged.stream;
  Stream<Launch> get onLaunchRemoved => _launchRemoved.stream;
  Stream<Launch> get onChangedActiveLaunch => _changedActiveLaunch.stream;

  void dispose() { }
}

class Launch {
  final LaunchManager manager;
  final String title;

  bool isTerminated = false;

  Launch(this.manager, this.title);

  // TODO: launch state changed

  //final Console console;

  bool get isRunning => !isTerminated;
  bool get isActive => manager.activeLaunch == this;

  // public?
  void launchTerminated() {
    if (isTerminated) return;
    isTerminated = true;
    manager._launchChanged.add(this);
  }

}

// TODO: stdout, stderr, exit code
class Console {

}
