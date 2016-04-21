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

  FlutterExt(this.serviceWrapper) {
    _init();
  }

  VmService get service => serviceWrapper.service;

  bool get isFlutter => enabled.value;

  Future debugPaint(bool enabled) {
    return service.callServiceExtension(
      '$_flutterPrefix.debugPaint',
      isolateId: isolateId,
      args: { 'enabled': enabled }
    );
  }

  Future repaintRainbow(bool enabled) {
    return service.callServiceExtension(
      '$_flutterPrefix.repaintRainbow',
      isolateId: isolateId,
      args: { 'enabled': enabled }
    );
  }

  Future timeDilation(double dilation) {
    return service.callServiceExtension(
      '$_flutterPrefix.timeDilation',
      isolateId: isolateId,
      args: { 'timeDilation': dilation }
    );
  }

  Future performanceOverlay(bool enabled) {
    return service.callServiceExtension(
      '$_flutterPrefix.showPerformanceOverlay',
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
      this.isolateId = isolateId;
      enabled.value = true;
    }

    _logger.fine('Found ${extension}.');

    services.add(extension);
  }
}
