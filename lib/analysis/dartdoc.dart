
library atom.dartdoc;

import 'dart:async';
import 'dart:html' show DivElement;

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:markdown/markdown.dart' as markdown;

import '../analysis_server.dart';
import '../atom_utils.dart';
import '../elements.dart';
import '../state.dart';

class DartdocHelper implements Disposable {
  Disposables _disposables = new Disposables();
  DartdocControl _control;

  DartdocHelper() {
    _disposables.add(atom.commands.add('atom-text-editor', 'dartlang:show-dartdoc', (event) {
      _handleDartdoc(event);
    }));

    editorManager.dartProjectEditors.onActiveEditorChanged.listen(_activateEditor);
  }

  void dispose() {
    _disposables.dispose();
    _hideControl();
  }

  void _activateEditor(TextEditor editor) {
    _hideControl();
  }

  void _hideControl() {
    if (_control != null) _control.dispose();
    _control = null;
  }

  void _handleDartdoc(AtomEvent event) {
    if (!analysisServer.isActive) {
      _hideControl();
      atom.beep();
      return;
    }

    bool explicit = true;

    TextEditor editor = event.editor;
    Range range = editor.getSelectedBufferRange();
    int offset = editor.getBuffer().characterIndexForPosition(range.start);

    Job job = new AnalysisRequestJob('dartdoc', () {
      return analysisServer.getHover(editor.getPath(), offset).then((HoverResult result) {
        if (result == null) return;

        _handleHoverResult(result, editor, explicit);
      });
    });
    job.schedule();
  }

  void _handleHoverResult(HoverResult result, TextEditor editor, bool explicit) {
    _hideControl();

    if (result.hovers.isEmpty) {
      if (explicit) atom.beep();
      return;
    }

    HoverInformation hover = result.hovers.first;

    _control = new DartdocControl(editor);
    _control.setTitle(_title(hover));
    _control.body = _render(hover);
    _control.setFooter(hover.containingClassDescription, hover.elementKind,
        _getLibraryName(hover));
  }

  static String _title(HoverInformation hover) {
    if (hover.elementDescription != null) return hover.elementDescription;
    if (hover.staticType != null) return hover.staticType;
    if (hover.propagatedType != null) return hover.propagatedType;
    return 'Dartdoc';
  }

  static String _render(HoverInformation hover) {
    StringBuffer buf = new StringBuffer();

    void writeTitle(String title, String desc) {
      if (desc != null && desc.isNotEmpty) {
        buf.write(
            "<span class='inline-block highlight'>${title}</span> ${desc}<br>\n");
      }
    };

    writeTitle('propagated type', hover.propagatedType);

    if (hover.dartdoc != null) {
      if (buf.isNotEmpty) buf.write('<br>');

      if (hover.dartdoc.contains(' class="material-icons')) {
        // <p><i class="material-icons md-36">menu</i> &#x2014; material...</p>
        buf.write('\n${hover.dartdoc}\n');
      } else {
        String html = markdown.markdownToHtml(hover.dartdoc, linkResolver: _resolve);
        buf.write('\n${html}\n');
      }
    }

    return buf.toString();
  }

  static markdown.Node _resolve(String name) {
    // TODO: Resolve these to linkable elements?
    return new markdown.Element.text('code', name);
  }

  static String _getLibraryName(HoverInformation hover) {
    String name = hover.containingLibraryName;
    if (name != null && name.isNotEmpty) return name;
    name = hover.containingLibraryPath;
    if (name == null || name.isEmpty) return null;
    int index = name.lastIndexOf('/');
    if (index != -1) name = name.substring(index + 1);
    index = name.lastIndexOf(r'\');
    if (index != -1) name = name.substring(index + 1);
    return name;
  }
}

class DartdocControl extends CoreElement {
  Disposable _cmdDispose;
  StreamSubscription _sub;

  CoreElement _titleDiv;
  CoreElement _bodyDiv;
  CoreElement _footerDiv;

  // <atom-panel class='modal'>
  // select-list popover-list
  DartdocControl(TextEditor editor) : super('div', classes: 'dartdoc-tooltip select-list popover-list') {
    id = 'dartdoc-tooltip';

    _cmdDispose = atom.commands.add('atom-workspace', 'core:cancel', (_) => dispose());
    _sub = editor.onDidDestroy.listen((_) => dispose());

    _titleDiv = add(div(c: 'dartdoc-title')); // panel-heading
    _bodyDiv = add(div(c: 'dartdoc-body')); // panel-body
    _footerDiv = add(div(c: 'dartdoc-footer')); // panel-heading

    // `view` is a JsObject
    var view = editor.view;
    // But its parent is returned as a `DivElement`
    DivElement parent = view['parentElement'];
    // Which is confusing.
    parent.append(this.element);
  }

  void setTitle(String desc) {
    _titleDiv.element.children.clear();

    _titleDiv.add(div(text: desc, c: 'inline-block text-highlight'));
  }

  set body(String value) {
    if (value.isNotEmpty) {
      _bodyDiv.element.setInnerHtml(value, validator: new PermissiveNodeValidator());
    } else {
      _bodyDiv.add(para(text: 'No documentation.', c: 'text-subtle'));
    }
  }

  void setFooter(String className, String kind, String libraryName) {
    _footerDiv.element.children.clear();

    if (className != null) {
      _footerDiv.add(div(text: className, c: 'inline-block highlight-success'));
    }

    if (kind != null) {
      _footerDiv.add(div(text: kind, c: 'inline-block highlight-success'));
    }

    _footerDiv.add(span()..element.innerHtml = '&nbsp;');

    if (libraryName != null) {
      _footerDiv.add(div(text: libraryName, c: 'inline-block highlight-info pull-right'));
    }
  }

  void dispose() {
    _sub.cancel();
    _cmdDispose.dispose();
    super.dispose();
  }
}
