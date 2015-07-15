
import 'dart:html' show Element, window;

//import 'package:markdown/markdown.dart';

import '../analysis_server.dart';
import '../atom.dart';
import '../state.dart';
import '../utils.dart';

class DartdocHelper implements Disposable {
  Disposables _disposables = new Disposables();

  DartdocHelper() {
    _disposables.add(atom.commands.add('atom-text-editor', 'dartlang:show-dartdoc', (event) {
      _handleDartdoc(event);
    }));

    editorManager.dartProjectEditors.onActiveEditorChanged.listen(_activateEditor);
    _activateEditor(editorManager.dartProjectEditors.activeEditor);
  }

  void dispose() => _disposables.dispose();

  void _activateEditor(TextEditor editor) {
    // TODO: remove old listeners

    if (editor == null) return;
    if (!analysisServer.isActive) return;
    
    // TODO: add new listeners

    print(editor);

    dynamic view = editor.view;
    window.console.log(view);

    //Element e = view.obj;
  }

  void _handleDartdoc(AtomEvent event) {
    if (!analysisServer.isActive) {
      atom.beep();
      return;
    }

    bool explicit = true;

    TextEditor editor = event.editor;
    Range range = editor.getSelectedBufferRange();
    int offset = editor.getBuffer().characterIndexForPosition(range.start);
    analysisServer.getHover(editor.getPath(), offset).then((HoverResult result) {
      if (result.hovers.isEmpty) {
        if (explicit) atom.beep();
        return;
      }

      HoverInformation hover = result.hovers.first;
      atom.notifications.addInfo(_title(hover),
          dismissable: true, detail: _render(hover));
    });
  }

  static String _title(HoverInformation hover) {
    if (hover.elementDescription != null) return hover.elementDescription;
    if (hover.staticType != null) return hover.staticType;
    if (hover.propagatedType != null) return hover.propagatedType;
    return 'Dartdoc';
  }

  static String _render(HoverInformation hover) {
    StringBuffer buf = new StringBuffer();
    if (hover.containingLibraryName != null) buf
        .write('library: ${hover.containingLibraryName}\n');
    if (hover.containingClassDescription != null) buf
        .write('class: ${hover.containingClassDescription}\n');
    if (hover.propagatedType != null) buf
        .write('propagated type: ${hover.propagatedType}\n');
    // TODO: Translate markdown.
    if (hover.dartdoc != null) buf.write('\n${_renderMarkdownToText(hover.dartdoc)}\n');
    return buf.toString();
  }

  static String _renderMarkdownToText(String str) {
    if (str == null) return null;

    StringBuffer buf = new StringBuffer();

    List<String> lines = str.replaceAll('\r\n', '\n').split('\n');

    for (String line in lines) {
      if (line.trim().isEmpty) {
        buf.write('\n');
      } else {
        buf.write('${line.trimRight()} ');
      }
    }

    return buf.toString();
  }
}
