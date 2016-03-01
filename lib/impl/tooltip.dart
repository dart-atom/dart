import 'dart:async';
import 'dart:html' as html;
import 'dart:js';

import 'package:atom_dartlang/analysis_server.dart';
import 'package:atom_dartlang/elements.dart';
import 'package:atom_dartlang/state.dart';
import 'package:logging/logging.dart';

import '../atom.dart';
import '../projects.dart';
import '../utils.dart';

final Logger _logger = new Logger('atom.tooltip');

/// Controls the hover tooltip with type information feature, capable of installing the feature
/// into every active .dart editor.
class TooltipController implements Disposable {
  Disposables _disposables = new Disposables();

  TooltipController() {
    Timer.run(() {
      _disposables.add(atom.workspace.observeTextEditors(_installInto));
    });
  }

  void dispose() {
    _disposables.dispose();
  }

  /// Installs the feature into [editor] if it responsible for a .dart file, noop if not.
  void _installInto(TextEditor editor) {
    if (!isDartFile(editor.getPath())) return;

    new TooltipManager(editor);
  }
}

/// Manages the display of tooltips for a single [TextEditor].
class TooltipManager implements Disposable {
  final TextEditor _editor;
  final html.Element _root;

  TooltipElement _tooltipElement;
  StreamSubscriptions _subs = new StreamSubscriptions();

  TooltipManager(TextEditor editor)
      : this._editor = editor,
        _root = editor.view['shadowRoot'] {
    _subs.add(_editor.onDidDestroy.listen((_) => dispose()));

    if (_root == null) {
      _logger.warning("The editor's shadow root is null.");
    } else {
      _install();
    }
  }

  void _install() {
    _root.addEventListener('mousemove', (html.MouseEvent e) {
      if (!_isTooltipEnabled) return;

      int offset = _offsetFromMouseEvent(e);
      new AnalysisRequestJob('hover-tooltip', () {
        return analysisServer.getHover(_editor.getPath(), offset).then((HoverResult result) {
          if (result == null) return;

          result.hovers.forEach((HoverInformation h) {
            // Get rid of previous tooltips.
            _tooltipElement?.dispose();
            _tooltipElement =
                new TooltipElement(_editor, content: _tooltipContent(h), position: e.offset);
          });
        });
      }).schedule();
    });

    _root.addEventListener('mouseout', (_) => _disposeTooltip());
    _root.addEventListener('keydown', (_) => _disposeTooltip());
  }

  /// Returns true if the tooltip feature is enabled.
  bool get _isTooltipEnabled => atom.config.getValue('$pluginId.hoverTooltip');

  /// Returns the offset in the current buffer corresponding to the screen position of the
  /// [MouseEvent].
  int _offsetFromMouseEvent(html.MouseEvent e) {
    JsObject component = _editor.view['component'];
    Point bufferPt = component.callMethod('screenPositionForMouseEvent', [e]);
    return _editor.getBuffer().characterIndexForPosition(bufferPt);
  }

  /// Returns the content to put into the tooltip based on [hover].
  String _tooltipContent(HoverInformation hover) =>
      hover.elementDescription ?? hover.staticType ?? hover.propagatedType;

  void _disposeTooltip() {
    _tooltipElement?.dispose();
  }

  @override
  void dispose() {
    _disposeTooltip();
  }
}

/// Basic tooltip element with single [String] content capable of attaching itself to a [TextEditor]
/// at a given position relative to its top,left corner.
class TooltipElement extends CoreElement {
  static const int _offset = 12;

  final String content;

  Disposable _cmdDispose;
  StreamSubscription _sub;

  TooltipElement(TextEditor editor, {this.content, html.Point position})
      : super('div', classes: 'hover-tooltip') {
    id = 'hover-tooltip';

    _cmdDispose = atom.commands.add('atom-workspace', 'core:cancel', (_) => dispose());
    _sub = editor.onDidDestroy.listen((_) => dispose());

    // Set position at the mouseevent coordinates.
    int x = position.x + _offset;
    int y = position.y + _offset;
    attributes['style'] = 'top: ${y}px; left: ${x}px;';

    // Actually create the tooltip element.
    add(div(c: 'hover-tooltip-title')).add(div(text: content, c: 'inline-block'));

    // Attach the tooltip to the editor view.
    html.DivElement parent = editor.view['parentElement'];
    if (parent == null) return;
    parent.append(this.element);
  }

  void dispose() {
    _sub.cancel();
    _cmdDispose.dispose();
    super.dispose();
  }
}
