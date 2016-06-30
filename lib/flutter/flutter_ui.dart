
import '../debug/debugger.dart';
import '../debug/observatory_debugger.dart';
import '../elements.dart';
import '../flutter/flutter_ext.dart';

// TODO(devoncarew): We need to re-do the UI for the Flutter section to better
// fit more elements (like a FPS label and the current route text).

class FlutterSection {
  final DebugConnection connection;

  CoreElement routeElement;
  bool isDebugDrawing = false;
  bool isRepaintRainbow = false;
  bool isSlowAnimations = false;
  bool isPerformanceOverlay = false;

  FlutterSection(this.connection, CoreElement element) {
    element.add([
      div().add([
        span(text: 'Flutter', c: 'overflow-hidden-ellipsis'),
        routeElement = span(c: 'debugger-secondary-info')
      ]),
      table()..add([
        tr()..add([
          td()..add([
            new CoreElement('label')..add([
              new CoreElement('input')
                ..setAttribute('type', 'checkbox')
                ..click(_toggleDrawing),
              span(text: 'Debug drawing', c: 'text-subtle')
            ])
          ]),
          td()..add([
            new CoreElement('label')..add([
              new CoreElement('input')
                ..setAttribute('type', 'checkbox')
                ..click(_toggleRepaintRainbow),
              span(text: 'Repaint rainbow', c: 'text-subtle')
            ])
          ])
        ]),
        tr()..add([
          td()..add([
            new CoreElement('label')..add([
              new CoreElement('input')
                ..setAttribute('type', 'checkbox')
                ..click(_togglePerformanceOverlay),
              span(text: 'Performance overlay', c: 'text-subtle')
            ])
          ]),
          td()..add([
            new CoreElement('label')..add([
              new CoreElement('input')
                ..setAttribute('type', 'checkbox')
                ..click(_toggleSlowAnimations),
              span(text: 'Slow animations', c: 'text-subtle')
            ])
          ])
        ])
      ])
    ]);

    element.hidden(true);

    if (connection is ObservatoryConnection) {
      ObservatoryConnection obs = connection;
      obs.flutterExtension.enabled.observe((value) {
        if (value) {
          element.hidden(false);
        }
      });
      // TODO: We should have this be automatic with the onExtensionEvent call.
      obs.service.streamListen('Extension');
      obs.service.onExtensionEvent
        .where((event) => event.extensionKind == 'Flutter.RouteChanged')
        .listen((event) {
          String route = event.extensionData.data['route'];
          routeElement.text = route ?? '';
        });
    }
  }

  FlutterExt get flutterExtension =>
    (connection as ObservatoryConnection).flutterExtension;

  void _toggleDrawing() {
    isDebugDrawing = !isDebugDrawing;
    flutterExtension.debugPaint(isDebugDrawing);
  }

  void _toggleRepaintRainbow() {
    isRepaintRainbow = !isRepaintRainbow;
    flutterExtension.repaintRainbow(isRepaintRainbow);
  }

  void _toggleSlowAnimations() {
    isSlowAnimations = !isSlowAnimations;
    flutterExtension.timeDilation(isSlowAnimations ? 5.0 : 1.0);
  }

  void _togglePerformanceOverlay() {
    isPerformanceOverlay = !isPerformanceOverlay;
    flutterExtension.performanceOverlay(isPerformanceOverlay);
  }
}
