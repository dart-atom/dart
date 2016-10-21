
import 'dart:async';

import 'package:logging/logging.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import '../debug/observatory.dart';
import '../utils.dart';

const String _flutterPrefix = 'ext.flutter';

final Logger _logger = new Logger('atom.flutter_ext');

/// Flutter specific debugging extensions.
///
/// This includes things like adjusting the `debugPaint` and `timeDilation`
/// values.
class FlutterExt {
  final ServiceWrapper serviceWrapper;
  final Property<bool> enabled = new Property(false);

  String isolateId;
  Set<String> services = new Set();

  Map<String, dynamic> _reapply = {};

  FlutterExt(this.serviceWrapper) {
    _init();
  }

  VmService get service => serviceWrapper.service;

  bool get isFlutter => enabled.value;

  Future debugPaint(bool enabled) {
    const String key = '$_flutterPrefix.debugPaint';

    if (enabled) {
      _reapply[key] = () => debugPaint(true);
    } else {
      _reapply.remove(key);
    }

    return service.callServiceExtension(
      key,
      isolateId: isolateId,
      args: { 'enabled': enabled }
    );
  }

  Future repaintRainbow(bool enabled) {
    const String key = '$_flutterPrefix.repaintRainbow';

    if (enabled) {
      _reapply[key] = () => repaintRainbow(true);
    } else {
      _reapply.remove(key);
    }

    return service.callServiceExtension(
      key,
      isolateId: isolateId,
      args: { 'enabled': enabled }
    );
  }

  Future timeDilation(double dilation) {
    const String key = '$_flutterPrefix.timeDilation';

    if (dilation == 1.0) {
      _reapply.remove(key);
    } else {
      _reapply[key] = () => timeDilation(dilation);
    }

    return service.callServiceExtension(
      key,
      isolateId: isolateId,
      args: { 'timeDilation': dilation }
    );
  }

  Future performanceOverlay(bool enabled) {
    const String key = '$_flutterPrefix.showPerformanceOverlay';

    if (enabled) {
      _reapply[key] = () => performanceOverlay(true);
    } else {
      _reapply.remove(key);
    }

    return service.callServiceExtension(
      key,
      isolateId: isolateId,
      args: { 'enabled': enabled }
    );
  }

  void _init() {
    serviceWrapper.allIsolates.forEach(_checkIsolate);
    serviceWrapper.onIsolateCreated.listen(_checkIsolate);

    serviceWrapper.service.onIsolateEvent.listen((Event event) {
      if (event.kind == EventKind.kServiceExtensionAdded) {
        if (event.extensionRPC.startsWith('$_flutterPrefix.')) {
          _registerExtension(event.isolate.id, event.extensionRPC);
        }
      }
    });
  }

  void _checkIsolate(ObservatoryIsolate isolate) {
    if (isolate.isolate.extensionRPCs == null) return;

    isolate.isolate.extensionRPCs.forEach((String ext) {
      if (ext.startsWith('$_flutterPrefix.')) {
        _registerExtension(isolate.id, ext);
      }
    });
  }

  void _registerExtension(String isolateId, String extension) {
    if (!isFlutter) {
      enabled.value = true;
    }

    this.isolateId = isolateId;

    _logger.finer('Found ${extension}.');

    if (services.contains(extension)) {
      if (_reapply.containsKey(extension)) {
        _reapply[extension]();
      }
    } else {
      services.add(extension);
    }
  }
}
