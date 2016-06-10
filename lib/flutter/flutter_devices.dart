
import 'dart:async';
import 'dart:collection' show LinkedHashSet;

import 'package:atom/atom.dart';
import 'package:atom/utils/dependencies.dart';
import 'package:atom/utils/disposable.dart';

import '../state.dart';
import 'flutter_daemon.dart';

export 'flutter_daemon.dart' show Device;

class FlutterDeviceManager implements Disposable {
  /// Flutter run / build modes.
  static List<BuildMode> runModes = [
    new BuildMode('debug', startPaused: true),
    new BuildMode('profile'),
    new BuildMode('release', supportsDebugging: false)
  ];

  StreamSubscriptions subs = new StreamSubscriptions();

  StreamController<Device> _selectedController = new StreamController.broadcast();
  StreamController<List<Device>> _devicesController = new StreamController.broadcast();
  StreamController<BuildMode> _modeController = new StreamController.broadcast();

  Device _selectedDevice;
  LinkedHashSet<Device> _devices = new LinkedHashSet<Device>();

  BuildMode _runMode = runModes.first;

  FlutterDeviceManager() {
    _updateForDaemon(_daemonManager.daemon);
    subs.add(_daemonManager.onDaemonAvailable.listen(_updateForDaemon));
  }

  BuildMode get runMode => _runMode;

  set runMode(BuildMode mode) {
    _runMode = mode;
    _modeController.add(_runMode);
  }

  void _updateForDaemon(FlutterDaemon daemon) {
    if (daemon == null) {
      // Clear devices.
      _devices.clear();
      _devicesController.add(devices);

      _validateSelection();
    } else {
      // query devices.
      _daemonManager.getDevices().then((List<Device> result) {
        _devices.clear();
        _devices.addAll(result);
        _devicesController.add(devices);

        _validateSelection();
      });

      // Listen for changes.
      subs.add(_daemonManager.onDeviceAdded.listen(_handleDeviceAdd));
      subs.add(_daemonManager.onDeviceChanged.listen(_handleDeviceChanged));
      subs.add(_daemonManager.onDeviceRemoved.listen(_handleDeviceRemoved));
    }
  }

  bool get isManagerActive => _daemonManager.daemon != null;

  Stream<bool> get onManagerActiveChanged => _daemonManager.onDaemonAvailable.map((daemon) => daemon != null);

  Stream<Device> get onSelectedChanged => _selectedController.stream;

  Stream<List<Device>> get onDevicesChanged => _devicesController.stream;

  Stream<BuildMode> get onModeChanged => _modeController.stream;

  Device get currentSelectedDevice => _selectedDevice;

  List<Device> get devices => _devices.toList();

  void setSelectedDeviceIndex(int index) {
    if (index >= 0 && index < _devices.length) {
      _selectedDevice = _devices.toList()[index];
      _selectedController.add(_selectedDevice);
    }
  }

  void dispose() {
    subs.cancel();
  }

  void _handleDeviceAdd(Device device) {
    atom.notifications.addSuccess("Found ${device.getLabel()}.");

    _devices.add(device);
    _devicesController.add(devices);

    _validateSelection();
  }

  void _handleDeviceChanged(Device device) {
    _devices.add(device);

    // If the IDs are the same, we replace the device object as the new one might
    // have updated information.
    if (_selectedDevice == device) {
      _selectedDevice = device;
    }

    _validateSelection();
  }

  void _handleDeviceRemoved(Device device) {
    atom.notifications.addInfo("${device.getLabel()} removed.");

    _devices.remove(device);
    _devicesController.add(devices);

    _validateSelection();
  }

  void _validateSelection() {
    Device selected = _selectedDevice;

    if (_devices.isEmpty) selected = null;
    if (!_devices.contains(selected)) selected = null;
    if (selected == null && _devices.isNotEmpty) selected = _devices.first;

    if (selected != _selectedDevice) {
      _selectedDevice = selected;
      _selectedController.add(selected);
    }
  }

  FlutterDaemonManager get _daemonManager => deps[FlutterDaemonManager];
}

class BuildMode {
  final String name;
  final bool supportsDebugging;
  final bool startPaused;

  BuildMode(this.name, { this.supportsDebugging: true, this.startPaused: false });

  String toString() => name;
}
