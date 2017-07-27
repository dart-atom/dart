import 'dart:async';
import 'dart:html' as html;

import 'package:atom/atom.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../analysis_server.dart';
import '../elements.dart';
import '../projects.dart';
import '../state.dart';

final Logger _logger = new Logger('atom.tooltip');

/// Controls the hover tooltip with type information feature, capable of
/// installing the feature into every active .dart editor.
class TooltipController implements Disposable {
  Disposables _disposables = new Disposables();

  TooltipController() {
    Timer.run(() {
      _disposables.add(atom.workspace.observeTextEditors(_installInto));
    });
  }

  /// Installs the feature into [editor] if it responsible for a .dart file,
  /// noop if not.
  void _installInto(TextEditor editor) {
    if (!isDartFile(editor.getPath())) return;

    new TooltipManager(editor);
  }

  void dispose() => _disposables.dispose();
}

/// Manages the display of tooltips for a single [TextEditor].
class TooltipManager implements Disposable {
  final TextEditor _editor;
  final html.Element _root;

  TooltipElement _tooltipElement;
  StreamSubscriptions _subs = new StreamSubscriptions();

  TooltipManager(TextEditor editor)
      : this._editor = editor,
        _root = editor.view {
    _subs.add(_editor.onDidDestroy.listen((_) => dispose()));

    if (_root == null) {
      _logger.warning("The editor's view is null.");
    } else {
      _install();
    }
  }

  void _install() {
    _root.addEventListener('mousemove', (html.Event event) {
      html.MouseEvent mouseEvent = event;
      if (!_isTooltipEnabled) return;
      if (!analysisServer.isActive) return;

      // TODO don't update if same selection
      // TODO wait a few milliseconds before showing?
      // TODO style text with underline if jump key is held and
      // we have a destination

      int offset = _offsetFromMouseEvent(mouseEvent);

      analysisServer.getHover(_editor.getPath(), offset).then((HoverResult result) {
        if (result == null) return;

        result.hovers.forEach((HoverInformation h) {
          // Get rid of previous tooltips.
          _tooltipElement?.dispose();
          _tooltipElement = new TooltipElement(_editor,
            content: _tooltipContent(h),
            position: _positionForScreenPosition(h.offset));
        });
      }).catchError((_) => null);
    });

    _root.addEventListener('mouseout', (_) => _disposeTooltip());
    _root.addEventListener('keydown', (_) => _disposeTooltip());
  }

  /// Returns true if the tooltip feature is enabled.
  bool get _isTooltipEnabled => atom.config.getValue('$pluginId.hoverTooltip');

  /// Returns the offset in the current buffer corresponding to the screen
  /// position of the [MouseEvent].
  int _offsetFromMouseEvent(html.MouseEvent e) {
    TextEditorComponent component = _editor.getElement().getComponent();
    var bufferPt = component.screenPositionForMouseEvent(e);
    return _editor.getBuffer().characterIndexForPosition(bufferPt);
  }

  html.Point _positionForScreenPosition(int offset) {
    TextEditorComponent component = _editor.getElement().getComponent();
    Point bufferPt = _editor.getBuffer().positionForCharacterIndex(offset);

    html.Point pixelPt = component.pixelPositionForScreenPosition(bufferPt);
    num scrollTop = component.scrollTop;
    num scrollLeft = component.scrollLeft;
    num gutterWidth = component.gutterWidth;
    var pt = new html.Point<num>(pixelPt.x - scrollLeft + gutterWidth, pixelPt.y - scrollTop);
    return pt;
  }

  /// Returns the content to put into the tooltip based on [hover].
  String _tooltipContent(HoverInformation hover) =>
      hover.elementDescription ?? hover.staticType ?? hover.propagatedType;

  void _disposeTooltip() => _tooltipElement?.dispose();

  void dispose() => _disposeTooltip();
}

/// Basic tooltip element with single [String] content capable of attaching
/// itself to a [TextEditor] at a given position relative to its top,left corner.
class TooltipElement extends CoreElement {
  static const int _offset = 12;

  final String content;

  Disposable _cmdDispose;
  StreamSubscription _sub;

  TooltipElement(TextEditor editor, {this.content, html.Point position})
      : super('div', classes: 'hover-tooltip') {
    id = 'hover-tooltip';

    print(position);

    _cmdDispose = atom.commands.add('atom-workspace', 'core:cancel', (_) => dispose());
    _sub = editor.onDidDestroy.listen((_) => dispose());

    // Set position at the mouseevent coordinates.
    int x = position.x - _offset;
    int y = position.y;

    var h = (editor.view as html.Element).clientHeight;

    attributes['style'] = 'bottom: ${h - y}px; left: ${x}px;';
    // Actually create the tooltip element.
    add(div(c: 'hover-tooltip-title')).add(div(text: content, c: 'inline-block'));

    // Attach the tooltip to the editor view.
    //html.DivElement parent = editor.view['parentElement'];
    html.Element parent = (editor.view as html.Element).parent;
    if (parent == null) return;
    parent.append(this.element);
  }

  void dispose() {
    _sub.cancel();
    _cmdDispose.dispose();
    super.dispose();
  }
}
