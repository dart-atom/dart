import 'dart:async';

import 'package:vm_service_lib/vm_service_lib.dart';

import '../debug/observatory.dart';
import '../utils.dart';

// TODO: be notified when isolates are discovered

class FlutterExt {
  final ServiceWrapper serviceWrapper;
  final Property<bool> enabled = new Property(false);

  String _isolateId;

  FlutterExt(this.serviceWrapper) {
    service.onEvent('_Logging').listen(_processLoggingEvent);

    _init();
  }

  VmService get service => serviceWrapper.service;

  bool get isFlutter => enabled.value;

  /// Pings the service client; a non-error response indicates that the client
  /// is a flutter client.
  Future<Response> flutter(String isolateId) {
    return service.callServiceExtension(
      'flutter',
      isolateId
    );
  }

  Future debugPaint(bool enabled) {
    return service.callServiceExtension(
      'flutter.debugPaint',
      _isolateId,
      args: { 'enabled': enabled }
    );
  }

  Future timeDilation(double dilation) {
    return service.callServiceExtension(
      'flutter.timeDilation',
      _isolateId,
      args: { 'timeDilation': dilation }
    );
  }

  Future _checkForFlutter(String isolateId) {
    return flutter(isolateId).then((_) {
        _isolateId = isolateId;
        enabled.value = true;
      }).catchError((e) => null);
  }

  void _init() {
    Future.forEach(serviceWrapper.allIsolates, (IsolateRef ref) {
      if (isFlutter) return new Future.value();
      return _checkForFlutter(ref.id);
    });

    serviceWrapper.onIsolateCreated.listen((IsolateRef ref) {
      if (isFlutter) return new Future.value();
      return _checkForFlutter(ref.id);
    });
  }

  void _processLoggingEvent(Event event) {
    Map<String, dynamic> json = event.json['logRecord'];

    InstanceRef loggerNameRef = InstanceRef.parse(json['loggerName']);
    String loggerName = loggerNameRef.valueAsString;

    InstanceRef messageRef = InstanceRef.parse(json['message']);
    String message = messageRef.valueAsString;

    if (loggerName == 'flutter') {
      if (message != null && message.contains('Flutter initialized')) {
        _isolateId = event.isolate.id;
        enabled.value = true;
      }
    }
  }
}
