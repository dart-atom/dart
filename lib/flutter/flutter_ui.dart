import '../debug/debugger.dart';
import '../debug/observatory_debugger.dart';
import '../elements.dart';
import '../flutter/flutter_ext.dart';

class FlutterSection {
  final DebugConnection connection;

  bool isDebugDrawing = false;
  bool isSlowAnimations = false;
  bool isFPSOverlay = false;

  FlutterSection(this.connection, CoreElement element) {
    element.add([
      div(
        text: 'Flutter',
        c: 'overflow-hidden-ellipsis'
      ),
      new CoreElement('label')..add([
        new CoreElement('input')
          ..setAttribute('type', 'checkbox')
          ..click(_toggleDrawing),
        span(text: ' debug drawing', c: 'text-subtle')
      ]),
      span(text: ' '), // so sad
      new CoreElement('label')..add([
        new CoreElement('input')
          ..setAttribute('type', 'checkbox')
          ..click(_toggleSlowAnimations),
        span(text: ' slower animations', c: 'text-subtle')
      ])
      // , span(text: ' '), // so sad
      // new CoreElement('label')..add([
      //   new CoreElement('input')
      //     ..setAttribute('type', 'checkbox')
      //     ..click(_toggleFPSOverlay),
      //   span(text: ' FPS overlay', c: 'text-subtle')
      // ])
    ]);

    element.hidden(true);

    if (connection is ObservatoryConnection) {
      ObservatoryConnection obs = connection;
      obs.flutterExtension.enabled.observe((value) {
        if (value) {
          element.hidden(false);
        }
      });
    }
  }

  FlutterExt get flutterExtension =>
    (connection as ObservatoryConnection).flutterExtension;

  void _toggleDrawing() {
    isDebugDrawing = !isDebugDrawing;
    flutterExtension.debugPaint(isDebugDrawing);
  }

  void _toggleSlowAnimations() {
    isSlowAnimations = !isSlowAnimations;
    flutterExtension.timeDilation(isSlowAnimations ? 5.0 : 1.0);
  }

  // void _toggleFPSOverlay() {
  //   isFPSOverlay = !isFPSOverlay;
  //   flutterExtension.fpsOverlay(isFPSOverlay);
  // }
}
