library atom.debug_ui;

import 'dart:async';
import 'dart:html' show document;

import '../elements.dart';
import '../utils.dart';
import 'debugger.dart';

// TODO: feedback when an operation is in progress (like pause, which can take
// a long time depending on the running app)

class DebugUIController implements Disposable {
  final DebugConnection connection;

  CoreElement ui;

  DebugUIController(this.connection) {
    CoreElement resume = button(c: 'btn icon-playback-play')..click(_resume);
    CoreElement pause = button(c: 'btn icon-playback-pause')..click(_pause);
    CoreElement stepIn = button(c: 'btn icon-chevron-down')..click(_stepIn);
    CoreElement stepOver = button(c: 'btn icon-chevron-right')..click(_stepOver);
    CoreElement stepOut = button(c: 'btn icon-chevron-up')..click(_stepOut);

    ui = div(c: 'debugger-ui btn-toolbar')..add([
      div(c: 'btn-group no-left')..add([
        resume, pause
      ]),
      div(c: 'btn-group')..add([
        stepIn, stepOver, stepOut
      ]),
      div(c: 'btn-group')..add([
        button(c: 'btn icon-primitive-square')..click(_terminate)
      ])
    ]);

    document.body.children.add(ui.element);

    void updateUi(bool suspended) {
      resume.enabled = suspended;
      pause.enabled = !suspended;
      stepIn.enabled = suspended;
      stepOut.enabled = suspended;
      stepOver.enabled = suspended;
    }

    updateUi(connection.isSuspended);
    connection.onSuspendChanged.listen(updateUi);

    _show();
  }

  void _show() {
    new Future.delayed(Duration.ZERO).then((_) {
      ui.toggleClass('debugger-show');
    });
  }

  Future _hide() {
    ui.toggleClass('debugger-show');
    return ui.element.onTransitionEnd.first;
  }

  // TODO: This is all temporary.
  _pause() => connection.pause();
  _resume() => connection.resume();
  _stepIn() => connection.stepIn();
  _stepOver() => connection.stepOver();
  _stepOut() => connection.stepOut();
  _terminate() => connection.terminate();

  void dispose() {
    _hide().then((_) {
      ui.dispose();
    });
  }
}
