import 'dart:async';

import 'package:vm_service_lib/vm_service_lib.dart';

import '../debug/observatory.dart';
import '../utils.dart';

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
      'flutter.debugPaint',
      isolateId,
      args: { 'enabled': enabled }
    );
  }

  Future timeDilation(double dilation) {
    return service.callServiceExtension(
      'flutter.timeDilation',
      isolateId,
      args: { 'timeDilation': dilation }
    );
  }

  Future fpsOverlay(bool showOverlay) {
    return service.callServiceExtension(
      'flutter.fpsOverlay',
      isolateId,
      args: { 'showOverlay': showOverlay }
    );
  }

  void _init() {
    serviceWrapper.allIsolates.forEach(_checkIsolate);
    serviceWrapper.onIsolateCreated.listen(_checkIsolate);

    serviceWrapper.service.onIsolateEvent.listen((Event event) {
      if (event.kind == EventKind.kServiceExtensionAdded) {
        if (event.extensionRPC.startsWith('flutter.')) {
          _registerExtension(event.isolate.id, event.extensionRPC);
        }
      }
    });
  }

  void _checkIsolate(ObservatoryIsolate isolate) {
    if (isolate.isolate.extensionRPCs == null) return;

    isolate.isolate.extensionRPCs.forEach((String ext) {
      if (ext.startsWith('flutter.')) {
        _registerExtension(isolate.id, ext);
      }
    });
  }

  void _registerExtension(String isolateId, String extension) {
    if (!isFlutter) {
      this.isolateId = isolateId;
      enabled.value = true;
    }

    services.add(extension);
  }
}
