import 'dart:async';

import 'package:vm_service_lib/vm_service_lib.dart';

import 'observatory_debugger.dart';

export 'observatory_debugger.dart' show ObservatoryIsolate;

abstract class ServiceWrapper {
  VmService get service;

  Iterable<ObservatoryIsolate> get allIsolates;

  Stream<ObservatoryIsolate> get onIsolateCreated;
  Stream<ObservatoryIsolate> get onIsolateFinished;
}
