import 'dart:async';

import 'package:vm_service_lib/vm_service_lib.dart';

abstract class ServiceWrapper {
  VmService get service;

  Iterable<IsolateRef> get allIsolates;

  Stream<IsolateRef> get onIsolateCreated;
  Stream<IsolateRef> get onIsolateFinished;
}
