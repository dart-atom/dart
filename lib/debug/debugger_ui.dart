library atom.debugger_ui;

import 'dart:async';
import 'dart:html' show DivElement, querySelector;
import 'dart:js' as js;

import 'package:logging/logging.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../editors.dart';
import '../elements.dart';
import '../state.dart';
import '../utils.dart';
import 'debugger.dart';
import 'utils.dart';
// import 'debugger_ui2.dart';

final Logger _logger = new Logger('atom.debugger_ui');

// TODO: feedback when an operation is in progress (like pause, which can take
// a long time depending on the running app)

class DebugUIController implements Disposable {
  final Disposables disposables = new Disposables();
  final DebugConnection connection;

  CoreElement ui;
  CoreElement frameTitle;
  //CoreElement frameLocation;
  CoreElement frameVars;

  Timer _debounceTimer;
  Marker _execMarker;

  DebugUIController(this.connection) {
    CoreElement resume = button(c: 'btn icon-playback-play')..click(_resume);
    CoreElement pause = button(c: 'btn icon-playback-pause')..click(_pause);
    CoreElement stepIn = button(c: 'btn icon-chevron-down')..click(_stepIn);
    CoreElement stepOver = button(c: 'btn icon-chevron-right')..click(_stepOver);
    CoreElement stepOut = button(c: 'btn icon-chevron-up')..click(_stepOut);

    CoreElement toolbar = div(c: 'btn-toolbar')..add([
      div(c: 'btn-group')..add([
        pause, resume
      ]),
      div(c: 'btn-group')..add([
        stepIn, stepOver, stepOut
      ]),
      div(c: 'btn-group')..add([
        button(c: 'btn icon-primitive-square')..click(_terminate)
      ])
    ]);

    CoreElement frameContent = div(c: 'debug-vars')..add([
      div(c: 'debug-title')..layoutHorizontal()..add([
        frameTitle = span(text: ' ', c: 'title')..flex()
        //frameLocation = span(c: 'badge')
      ]),
      div(c: 'select-list')..add([
        frameVars = ul(c: 'list-group')
      ])
    ]);

    //DebuggerView.showViewForConnection(connection);

    var temp = new DivElement();
    temp.setInnerHtml(
        '<atom-text-editor mini placeholder-text="evaluate:" '
          'data-grammar="source dart">'
        '</atom-text-editor>',
        treeSanitizer: new TrustedHtmlTreeSanitizer());
    var editorElement = temp.querySelector('atom-text-editor');
    js.JsFunction editorConverter = js.context['getTextEditorForElement'];
    TextEditor editor = new TextEditor(editorConverter.apply([editorElement]));
    editor.setGrammar(atom.grammars.grammarForScopeName('source.dart'));

    CoreElement footer = div(c: 'debug-footer')..add([
      temp
    ]);

    ui = div(c: 'debugger-ui')..layoutVertical()..add([
      div(c: 'debug-header')..add([
        toolbar
      ]),
      frameContent,
      footer
    ]);

    // debugger-ui atom-text-editor? atom-workspace
    disposables.add(atom.commands.add(footer.element, 'core:confirm', (_) {
      String text = editor.getText();
      flashSelection(editor, new Range.fromPoints(
          new Point.coords(0, 0),
          new Point.coords(0, text.length)
      ));
      _eval(text);
    }));

    // Oh, the travesty.
    //document.body.children.add(ui.element);
    //querySelector('atom-workspace').children.add(ui.element);
    js.context.callMethod('_domHoist', [ui.element, 'atom-workspace']);

    void updateUi(bool suspended) {
      resume.enabled = suspended;
      pause.enabled = !suspended;
      stepIn.enabled = suspended;
      stepOut.enabled = suspended;
      stepOver.enabled = suspended;

      if (_debounceTimer != null) {
        _debounceTimer.cancel();
        _debounceTimer = null;
      }

      if (!suspended) {
        // Put a brief debounce delay here when stepping to reduce flashing.
        _debounceTimer = new Timer(
            new Duration(milliseconds: 40),
            () => _updateVariables(suspended));
      } else {
        _updateVariables(suspended);
      }
    }

    updateUi(connection.isSuspended);
    _show();
    connection.onSuspendChanged.listen(updateUi);
  }

  void _updateVariables(bool suspended) {
    if (_debounceTimer != null) {
      _debounceTimer.cancel();
      _debounceTimer = null;
    }

    // Update the execution point.
    if (suspended && connection.topFrame != null) {
      connection.topFrame.getLocation().then((DebugLocation location) {
        _removeExecutionMarker();

        if (location != null) {
          _jumpToLocation(location, addExecMarker: true);
        }
      });
    } else {
      _removeExecutionMarker();
    }

    frameVars.clear();

    if (suspended) {
      if (connection.topFrame != null) {
        frameTitle.text = connection.topFrame.title;
        // frameLocation.text = connection.topFrame.cursorDescription;
        // frameLocation.hidden(false);

        List<DebugVariable> locals = connection.topFrame.locals;

        if (locals.isEmpty) {
          frameVars.add(em(text: '<no local variables>', c: 'text-muted'));
        } else {
          for (DebugVariable v in locals) {
            frameVars.add(li()..add([
              span(text: v.name, c: 'var-name'),
              span(text: v.valueDescription, c: 'var-value'),
            ]));
          }
        }
      } else {
        frameTitle.text = ' ';
        // frameLocation.hidden(true);
      }
    } else {
      // frameLocation.hidden(true);
      if (connection.isolate != null) {
        frameTitle.text = "Isolate '${connection.isolate.name}' running…";
      } else {
        frameTitle.text = ' ';
      }
    }
  }

  void _eval(String expression) {
    if (connection.topFrame == null) {
      atom.beep();
    } else {
      connection.topFrame.eval(expression).then((String result) {
        connection.launch.pipeStdio('${expression}: ${result}\n', subtle: true);
      }).catchError((e) {
        connection.launch.pipeStdio('${expression}: ${e}\n', error: true);
      });
    }
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

  void _jumpToLocation(DebugLocation location, {bool addExecMarker: false}) {
    if (statSync(location.path).isFile()) {
      // TODO: Do we also want to adjust the cursor position?
      editorManager.jumpToLocation(location.path).then((TextEditor editor) {
        // Ensure that the execution point is visible.
        editor.scrollToBufferPosition(
            new Point.coords(location.line - 1, location.column - 1), center: true);

        if (addExecMarker) {
          _execMarker?.destroy();

          // Update the execution location markers.
          _execMarker = editor.markBufferRange(
              debuggerCoordsToEditorRange(location.line, location.column),
              persistent: false);

          // The executing line color.
          editor.decorateMarker(_execMarker, {
            'type': 'line', 'class': 'debugger-executionpoint-line'
          });

          // The right-arrow.
          editor.decorateMarker(_execMarker, {
            'type': 'line-number', 'class': 'debugger-executionpoint-linenumber'
          });

          // The column marker.
          editor.decorateMarker(_execMarker, {
            'type': 'highlight', 'class': 'debugger-executionpoint-highlight'
          });
        }
      });
    } else {
      atom.notifications.addWarning("Cannot find file '${location.path}'.");
    }
  }

  void _removeExecutionMarker() {
    if (_execMarker != null) {
      _execMarker.destroy();
      _execMarker = null;
    }
  }

  // TODO: This is all temporary.
  _pause() => connection.pause();
  _resume() => connection.resume();
  _stepIn() => connection.stepIn();
  _stepOver() => connection.stepOver();
  _stepOut() => connection.stepOut();
  _terminate() => connection.terminate();

  void dispose() {
    disposables.dispose();
    _removeExecutionMarker();
    _hide().then((_) {
      // So sad.
      js.context.callMethod('_domRemove', [ui.element]);
      //ui.dispose();
    }).catchError((e) {
      _logger.warning('error when closing debugger ui', e);
    });
  }
}
