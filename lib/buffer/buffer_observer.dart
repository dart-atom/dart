library atom.buffer_observer;

import 'dart:async';

import 'package:frappe/frappe.dart';
import 'package:logging/logging.dart';

import '../analysis/formatting.dart';
import '../analysis_server.dart';
import '../atom.dart';
import '../state.dart';
import '../utils.dart';

final Logger _logger = new Logger('atom.buffer_observer');

class BufferObserverManager implements Disposable {
  List<BufferObserver> observers = [];
  OverlayManager overlayManager = new OverlayManager();

  BufferObserverManager() {
    // TODO: Fix editorManager.dartProjectEditors.
    editorManager.dartProjectEditors.openEditors.forEach(_newEditor);
    editorManager.dartProjectEditors.onEditorOpened.listen(_newEditor);
  }

  void _newEditor(TextEditor editor) {
    observers.add(new BufferUpdater(this, editor));
    observers.add(new BufferFormatter(this, editor));
  }

  void dispose() {
    observers.toList().forEach((obs) => obs.dispose());
    observers.clear();
    overlayManager.dispose();
  }

  bool remove(BufferObserver observer) => observers.remove(observer);
}

class BufferObserver extends Disposables {
  final BufferObserverManager manager;
  final TextEditor editor;

  BufferObserver(this.manager, this.editor);
}

class BufferFormatter extends BufferObserver {
  StreamSubscriptions _subs = new StreamSubscriptions();
  bool isFormatting = false;
  bool get formatOnSave => atom.config.getValue('dartlang.formatOnSave');

  BufferFormatter(manager, editor) : super(manager, editor) {
    _subs.add(this.editor.onDidSave.listen((_) {
      if (isFormatting) return;
      if (!formatOnSave) return;
      if (!analysisServer.isActive) return;
      if (!dartProject) return; // Breaks stand-alone dart files?

      isFormatting = true;
      FormattingHelper.formatEditor(editor, quiet: true).then((didFormat) {
        if (didFormat) editor.save();
        // This is a side-effect or bug in Dart:
        // This method will complete before the callbacks initiated by
        // the editor will be invoked. This is different from JavaScript,
        // which will invoke the callbacks first, then continue.
        //
        // To work around this, we set isFormatting = false outside of
        // the method scope.
        new Timer(new Duration(milliseconds: 10), () => isFormatting = false);
      });
    }));

    _subs.add(this.editor.onDidDestroy.listen((_) {
      dispose();
    }));
  }

  // TODO: Remove once we only watch Dart files that are in a Dart project.
  bool get dartProject => projectManager.getProjectFor(editor.getPath()) != null;

  void dispose() {
    _subs.cancel();
    manager.remove(this);
  }
}

/// Observe a TextEditor and notifies the analysis_server of any content changes
/// it should care about.
///
/// Although this class should use the "ChangeContentOverlay" route,
/// Atom doesn't provide us with diffs, so it is more expensive to calculate
/// the diffs than just remove the existing overlay and add a new one with
/// the changed content.
class BufferUpdater extends BufferObserver {
  final StreamSubscriptions _subs = new StreamSubscriptions();

  String path;

  BufferUpdater(manager, editor) : super(manager, editor) {
    path = editor.getPath();

    // Debounce atom onDidChange events; atom sends us several events as a file
    // is opening. The number of events is proportional to the file size. For
    // a file like dart:html, this is on the order of 800 onDidChange events.
    var onDidChangeSub = new EventStream(editor.onDidChange)
        .debounce(new Duration(milliseconds: 10))
        .listen(_didChange);

    _subs.add(onDidChangeSub);
    _subs.add(editor.onDidDestroy.listen(_didDestroy));

    addOverlay();
  }

  OverlayManager get overlayManager => manager.overlayManager;

  // TODO: Remove once we only watch Dart files that are in a Dart project.
  bool get dartProject => projectManager.getProjectFor(path) != null;

  void _didChange([_]) => changedOverlay();

  void _didDestroy([_]) => dispose();

  void addOverlay() {
    if (!dartProject) return;
    overlayManager.addOverlay(path, editor.getText());
  }

  void changedOverlay() {
    if (!dartProject) return;
    overlayManager.updateOverlay(path, editor.getText());
  }

  void removeOverlay() {
    if (!dartProject) return;
    overlayManager.removeOverlay(path);
  }

  void dispose() {
    super.dispose();

    removeOverlay();
    manager.remove(this);

    _subs.cancel();
  }
}

/// A class to manage the open overlays for Atom, and making sure that we're
/// reporting the correct overlay information to the analysis server.
class OverlayManager implements Disposable {
  final Map<String, OverlayInfo> overlays = {};
  StreamSubscription sub;

  OverlayManager() {
    sub = analysisServer.isActiveProperty.listen(_serverActive);
  }

  void addOverlay(String path, String data) {
    OverlayInfo overlay = overlays[path];

    if (overlay == null) {
      overlay = overlays[path] = new OverlayInfo(path, data);
      if (analysisServer.isActive) {
        _logger.fine("addContentOverlay('${path}')");
        _log(analysisServer.updateContent(
          path, new AddContentOverlay('add', data)
        ));
      }
    } else {
      overlay.count++;
    }
  }

  void updateOverlay(String path, String newData) {
    OverlayInfo overlay = overlays[path];

    if (overlay == null) {
      addOverlay(path, newData);
      return;
    }

    if (overlay.data != newData) {
      List<Edit> edits = simpleDiff(overlay.data, newData);
      int count = 1;
      List<SourceEdit> diffs = edits
          .map((e) => new SourceEdit(e.offset, e.length, e.replacement, id: '${count++}'))
          .toList();

      overlay.data = newData;

      _logger.fine("changedOverlayContent('${path}')");
      _log(analysisServer.updateContent(
          path, new ChangeContentOverlay('change', diffs)
      ));
    }
  }

  void removeOverlay(String path) {
    OverlayInfo overlay = overlays[path];
    if (overlay == null) return;

    overlay.count--;

    if (overlay.count == 0) {
      overlays.remove(path);

      _logger.fine("removeContentOverlay('${path}')");
      _log(analysisServer.updateContent(
        path, new RemoveContentOverlay('remove')
      ));
    }
  }

  void _serverActive(bool active) {
    if (overlays.isNotEmpty) {
      Map<String, dynamic> toSend = {};
      overlays.forEach((key, OverlayInfo info) {
        toSend[key] = new AddContentOverlay('add', info.data);
      });
      _log(analysisServer.server.analysis.updateContent(toSend));
    }
  }

  void dispose() {
    sub.cancel();
  }
}

/// Store information about the number iof overlays we have for an open file.
/// Each file can be open in multiple editors.
class OverlayInfo {
  final String path;
  int count = 1;
  String data;

  OverlayInfo(this.path, [this.data]);

}

void _log(Future f) {
  f.catchError((e) => _logger.warning('overlay call error; ${e}'));
}
