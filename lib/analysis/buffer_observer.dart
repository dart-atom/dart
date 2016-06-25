library atom.buffer_observer;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';
import 'package:logging/logging.dart';

import '../analysis/analysis_options.dart';
import '../analysis/formatting.dart';
import '../analysis_server.dart';
import '../impl/debounce.dart';
import '../projects.dart';
import '../state.dart';

final Logger _logger = new Logger('atom.buffer_observer');

class BufferObserverManager implements Disposable {
  List<BufferObserver> observers = [];
  Disposables disposables = new Disposables();
  OverlayManager overlayManager = new OverlayManager();

  BufferObserverManager() {
    // TODO: Fix editorManager.dartProjectEditors.
    editorManager.dartProjectEditors.openEditors.forEach(_newEditor);
    editorManager.dartProjectEditors.onEditorOpened.listen(_newEditor);

    // Create overlays for `.analysis_options` files.
    Timer.run(() {
      disposables.add(atom.workspace.observeTextEditors((editor) {
        String path = editor.getPath();
        if (path == null || !path.endsWith(analysisOptionsFileName)) return;

        if (fs.basename(path) == analysisOptionsFileName &&
            projectManager.getProjectFor(path) != null) {
          _newEditor(editor);
        }
      }));
    });
  }

  void _newEditor(TextEditor editor) {
    observers.add(new BufferUpdater(this, editor));
    if (isDartFile(editor.getPath())) {
      observers.add(new BufferFormatter(this, editor));
    }
  }

  void dispose() {
    disposables.dispose();
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
      if (!dartProject) return; // Breaks stand-alone dart files?

      isFormatting = true;
      FormattingManager.formatEditor(editor, quiet: true).then((didFormat) {
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
class BufferUpdater extends BufferObserver {
  final StreamSubscriptions _subs = new StreamSubscriptions();

  String path;

  BufferUpdater(BufferObserverManager manager, TextEditor editor) : super(manager, editor) {
    path = editor.getPath();

    // Debounce atom onDidChange events; atom sends us several events as a file
    // is opening. The number of events is proportional to the file size. For
    // a file like dart:html, this is on the order of 800 onDidChange events.
    StreamSubscription onDidChangeSub = editor.onDidChange
        .transform(new Debounce(new Duration(milliseconds: 10)))
        .listen(_didChange);

    _subs.add(onDidChangeSub);
    _subs.add(editor.onDidDestroy.listen(_didDestroy));
    _subs.add(editor.onDidChangeTitle.listen(_onDidChangeTitle));

    addOverlay();
  }

  OverlayManager get overlayManager => manager.overlayManager;

  // TODO: Remove once we only watch Dart files that are in a Dart project.
  bool get dartProject => projectManager.getProjectFor(path) != null;

  void _didChange([_]) => changedOverlay();

  void _onDidChangeTitle([_]) {
    removeOverlay();
    path = editor.getPath();
    addOverlay();
  }

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
    _serverActive(analysisServer.isActive);
    sub = analysisServer.onActive.listen(_serverActive);
    analysisServer.willSend = _willSend;
  }

  void addOverlay(String path, String data) {
    OverlayInfo overlay = overlays[path];

    if (overlay == null) {
      overlay = overlays[path] = new OverlayInfo(path, lastSent: data, toSend: data);
      if (analysisServer.isActive) {
        _logger.fine('addContentOverlay ${path}');
        _log(analysisServer.updateContent(path, new AddContentOverlay('add', data)));
        overlay.reset();
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

    if (overlay.toSend != newData) {
      if (analysisServer.isActive) {
        // On a content changed, start a timer instead of actually sending.
        overlay.sendData(newData);
      }
    }
  }

  void removeOverlay(String path) {
    OverlayInfo overlay = overlays[path];
    if (overlay == null) return;

    overlay.count--;

    if (overlay.count == 0) {
      overlays.remove(path);

      _logger.fine('removeContentOverlay ${path}');

      if (analysisServer.isActive) {
        _log(analysisServer.updateContent(path, new RemoveContentOverlay('remove')));
        overlay.reset();
      }
    }
  }

  void _willSend(String methodName) {
    // Flush any pending changes.
    _flush();
  }

  void _flush() {
    for (OverlayInfo overlay in overlays.values) {
      if (overlay.isDirty) overlay._flush();
    }
  }

  void _serverActive(bool active) {
    if (!active) return;

    if (overlays.isNotEmpty) {
      Map<String, dynamic> toSend = {};

      overlays.forEach((key, OverlayInfo overlay) {
        toSend[key] = new AddContentOverlay('add', overlay.toSend);
        overlay.reset();
      });

      _log(analysisServer.server.analysis.updateContent(toSend));
    }
  }

  void dispose() {
    analysisServer.willSend = null;
    sub.cancel();
  }
}

/// Store information about the number of overlays we have for an open file.
/// Each file can be open in multiple editors.
class OverlayInfo {
  final String path;

  String lastSent;
  String toSend;

  int count = 1;

  Timer _timer;

  OverlayInfo(this.path, {this.lastSent, this.toSend});

  bool get isDirty => lastSent != toSend;

  void sendData(String newData) {
    toSend = newData;
    _timer?.cancel();
    _timer = new Timer(new Duration(milliseconds: 400), _flush);
  }

  void _flush() {
    if (!analysisServer.isActive) return;

    _timer?.cancel();
    _timer = null;

    List<Edit> edits = simpleDiff(lastSent, toSend);
    int count = 1;
    List<SourceEdit> diffs = edits
      .map((e) => new SourceEdit(e.offset, e.length, e.replacement, id: '${count++}'))
      .toList();

    lastSent = toSend;

    _logger.finer('changedOverlayContent ${path}');

    _log(analysisServer.updateContent(path, new ChangeContentOverlay('change', diffs)));
  }

  // Mark all data as sent and cancel any timers.
  void reset() {
    lastSent = toSend;
    _timer?.cancel();
  }
}

void _log(Future f) {
  f.catchError((e) => _logger.warning('overlay call error; ${e}'));
}
