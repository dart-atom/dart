library atom.debug_ui;

import 'dart:html' show document;

//import 'package:frappe/frappe.dart';

import '../elements.dart';
import '../utils.dart';
import 'debug.dart';

class DebugUIController implements Disposable {
  final DebugConnection connection;

  CoreElement ui;

  DebugUIController(this.connection) {
    ui = div(c: 'debug-ui btn-toolbar')..add([
      div(c: 'btn-group no-left')..add([
        button(c: 'btn icon-playback-pause')..click(_pause),
        button(c: 'btn icon-playback-play')..click(_resume)
      ]),
      div(c: 'btn-group')..add([
        button(c: 'btn icon-chevron-down')..click(_stepIn),
        button(c: 'btn icon-chevron-right')..click(_stepOver),
        button(c: 'btn icon-chevron-up')..click(_stepOut),
      ]),
      div(c: 'btn-group')..add([
        button(c: 'btn icon-primitive-square')..click(_terminate)
      ])
    ]);

    document.body.children.add(ui.element);
  }

  // TODO: This is all temporary.
  _pause() => connection.pause();
  _resume() => connection.resume();
  _stepIn() => connection.stepIn();
  _stepOver() => connection.stepOver();
  _stepOut() => connection.stepOut();
  _terminate() => connection.terminate();

  void dispose() {
    ui.dispose();
  }
}
