import 'dart:async';
import 'dart:html' show AnchorElement, InputElement;

import 'package:atom/atom.dart';
import 'package:atom/node/package.dart';
import 'package:atom/node/shell.dart';
import 'package:atom/utils/disposable.dart';
import 'package:atom/utils/string_utils.dart';
import 'package:logging/logging.dart';

import '../analysis/analysis_server_lib.dart' show DiagnosticsResult, ContextData;
import '../atom_utils.dart';
import '../elements.dart';
import '../material.dart';
import '../sdk.dart';
import '../state.dart';
import '../usage.dart' show trackCommand;
import '../views.dart';

final String _statusOpenKey = 'statusOpen';

final Logger _logger = new Logger('atom.status');

class StatusViewManager implements Disposable {
  Disposables disposables = new Disposables();

  StatusViewManager() {
    disposables.add(atom.commands.add('atom-workspace', '${pluginId}:show-plugin-status', (_) {
      toggleView();
    }));
    disposables.add(atom.commands.add('atom-workspace', '${pluginId}:analysis-server-status', (_) {
      showSection('analysis-server');
    }));
    disposables.add(atom.commands.add('atom-workspace', '${pluginId}:show-sdk-info', (_) {
      showSection('dart-sdk');
    }));

    if (state[_statusOpenKey] == true) {
      toggleView();
    }
  }

  void dispose() => disposables.dispose();

  void showSection(String sectionName) {
    if (!viewGroupManager.hasViewId(pluginId)) {
      toggleView();
    }

    StatusView view = viewGroupManager.getViewById(pluginId);
    view.showSection(sectionName);
  }

  void toggleView() {
    if (viewGroupManager.hasViewId(pluginId)) {
      if (viewGroupManager.isActiveId(pluginId)) {
        viewGroupManager.removeViewId(pluginId);
        state[_statusOpenKey] = false;
      } else {
        viewGroupManager.activateView(pluginId);
      }
    } else {
      viewGroupManager.addView('right', new StatusView());
    }
  }
}

class StatusView extends View {
  StreamSubscriptions subs = new StreamSubscriptions();

  final Map<String, CoreElement> _sections = {};

  StatusView() {
    CoreElement subtitle;
    CoreElement container;

    content.toggleClass('tab-scrollable-container');
    content.toggleClass('plugin-status');
    content.add([
      div(c: 'view-header view-header-static')..add([
        div(text: 'Dart plugin status', c: 'view-title'),
        subtitle = div(c: 'view-subtitle')
      ]),
      container = div(c: 'tab-scrollable')
    ]);

    _getPlatformVersions().then((str) {
      subtitle.text = str;
    });

    CoreElement last;

    last = _registerSection('plugin', _createPluginSection(container));
    last = _registerSection('dart-sdk', _createDartSdkSection(container));
    last = _registerSection('analysis-server', _createAnalysisServerSection(container));
    last = _registerSection('analytics', _createAnalyticsSection(container));

    last.toggleClass('view-section-last');

    state[_statusOpenKey] = true;
  }

  CoreElement _registerSection(String sectionId, CoreElement element) {
    for (var link in element.element.querySelectorAll('a')) {
      AnchorElement aRef = link;
      link.onClick.listen((_) => shell.openExternal(aRef.href));
    }

    _sections[sectionId] = element;

    return element;
  }

  CoreElement _createPluginSection(CoreElement container) {
    CoreElement section = container.add(div(c: 'view-section'));
    StatusHeader header = new StatusHeader(section);
    header.title.text = '${pluginId} plugin';
    atomPackage.getPackageVersion().then((str) {
      header.subtitle.text = str;
    });

    header.toolbar.add(new MIconButton('icon-tools')..click(() {
      atom.workspace.openConfigPage(packageID: 'dartlang');
    }))..tooltip = 'Settings';

    CoreElement text = section.add(div());
    text.setInnerHtml(
      'For help using this plugin, please see our '
      '<a href="https://dart-atom.github.io/dartlang/">getting started</a> '
      'guide.'
    );

    CoreElement buttons = _addButtons(section);
    buttons.add(button(text: 'Check for Updates', c: 'btn')..click(() {
      atom.workspace.open('atom://config/updates');
    }));
    buttons.add(button(text: 'Report Issue…', c: 'btn')..click(() {
      getSystemDescription().then((String description) {
        shell.openExternal('https://github.com/dart-atom/dartlang/issues/new?'
            'body=${Uri.encodeComponent(description)}');
      });
    }));

    return section;
  }

  ViewSection _createDartSdkSection(CoreElement container) {
    CoreElement section = container.add(div(c: 'view-section'));
    StatusHeader header = new StatusHeader(section);
    header.title.text = 'Dart SDK';

    // TODO: This should be an editable text field.
    CoreElement pathElement;

    section.add([
      pathElement = div(c: 'overflow-hidden-ellipsis bottom-margin')
        ..element.style.alignSelf = 'flex-end'
    ]);

    CoreElement text = section.add(div());
    text.setInnerHtml(
      'Visit <a href="https://www.dartlang.org/downloads/">dartlang.org</a> for '
      'information on installing a Dart SDK for your platform.');

    var update = (Sdk sdk) {
      if (sdk == null) {
        header.subtitle.text = 'no SDK configured';
        pathElement.text = '';
        pathElement.tooltip = '';
      } else {
        sdk.getVersion().then((ver) {
          header.subtitle.text = ver;
        });
        pathElement.text = sdk.path;
        pathElement.tooltip = sdk.path;
      }
    };
    update(sdkManager.sdk);
    subs.add(sdkManager.onSdkChange.listen(update));

    CoreElement buttons = _addButtons(section);
    buttons.add(button(text: 'Browse…', c: 'btn')..click(_handleSdkBrowse));
    buttons.add(button(text: 'Auto-locate', c: 'btn')..click(() {
      new SdkLocationJob(sdkManager).schedule();
    }));

    return section;
  }

  ViewSection _createAnalysisServerSection(CoreElement container) {
    CoreElement section = container.add(div(c: 'view-section'));
    StatusHeader header = new StatusHeader(section);
    CoreElement start;
    CoreElement reanalyze;
    CoreElement stop;
    CoreElement status;

    String version;

    header.title.text = 'Analysis server';

    Strobe strobeIncoming = new Strobe(
      text: ' ', classes: 'icon-triangle-left'
    )..element.style.marginLeft = '0.3em';
    Strobe strobeOutgoing = new Strobe(
      text: ' ', classes: 'icon-triangle-right'
    );
    header.toolbar.add(strobeIncoming);
    header.toolbar.add(strobeOutgoing);

    var update = ([bool _]) {
      start.disabled = analysisServer.isActive;
      reanalyze.enabled = analysisServer.isActive;
      stop.enabled = analysisServer.isActive;

      if (!analysisServer.isActive) {
        header.subtitle.text = '';
        status.text = 'not active';
      } else {
        status.text = analysisServer.isBusy ? 'analyzing…' : 'idle';

        Future f = version != null
          ? new Future.value(version)
          : analysisServer.server.server.getVersion().then((v) => v.version);
        f.then((v) {
          version = v;
          header.subtitle.text = version;
        });
      }
    };

    // Hook up the strobes.
    // final Duration _duration = new Duration(seconds: 3);

    // CoreElement response;
    // Timer timer;

    // section.add([
    //   div(c: 'overflow-hidden-ellipsis bottom-margin')..add([
    //     response = span(c: 'text-subtle overflow-hidden-ellipsis')
    //   ])
    // ]);

    var updateTrafficIncoming = (String str) {
      // Don't show the text for the diagnostic command.
      if (str.contains('"result":{"contexts":')) return;
      strobeIncoming.strobe();
    };
    subs.add(analysisServer.onReceive.listen(updateTrafficIncoming));

    var updateTrafficOutgoing = (String str) {
      // Don't show the text for the diagnostic command.
      if (str.contains('"diagnostic.getDiagnostics"')) return;
      strobeOutgoing.strobe();
    };
    subs.add(analysisServer.onSend.listen(updateTrafficOutgoing));

    // Show diagnostics.
    section.add(div()..add([
      span(text: 'status:', c: 'diagnostics-title'),
      status = span(c: 'diagnostics-data')
    ]));
    CoreElement diagnostics = section.add(div(c: 'bottom-margin'));
    _createDiagnostics(diagnostics);

    CoreElement buttons = _addButtons(section);
    buttons.add([
      start = button(text: 'Start', c: 'btn')..click(_handleServerStart),
      reanalyze = button(text: 'Reanalyze', c: 'btn')..click(_handleReanalyze),
      stop = button(text: 'Shutdown', c: 'btn')..click(_handleServerStop),
    ]);

    update();
    subs.add(analysisServer.onBusy.listen(update));
    subs.add(analysisServer.onActive.listen((_) {
      version = null;
      update();
    }));

    return section;
  }

  Timer _diagnosticTimer;

  void _createDiagnostics(CoreElement diagnostics) {
    CoreElement contextCount;
    CoreElement fileCount;
    CoreElement taskQueueCount;

    var updateUI = (DiagnosticsResult result) {
      // context count, explicitFileCount + implicitFileCount, workItemQueueLength
      if (result == null) {
        contextCount.text = '—';
        fileCount.text = '—';
        taskQueueCount.text = '—';
      } else {
        contextCount.text = commas(result.contexts.length);
        int count = result.contexts
          .map((c) => c.explicitFileCount + c.implicitFileCount)
          .fold(0, (a, b) => a + b);
        fileCount.text = commas(count);
        int queue = result.contexts
          .map((ContextData c) => c.workItemQueueLength)
          .fold(0, (a, b) => a + b);
        taskQueueCount.text = commas(queue);
      }
    };

    var handleActive = (bool active) {
      if (active) {
        _diagnosticTimer = new Timer.periodic(new Duration(seconds: 1), (_) {
          analysisServer.server.diagnostic.getDiagnostics().then((result) {
            updateUI(result);
          }).catchError((e, st) {
            _logger.info('error from diagnostic.getDiagnostics()', e);
            _diagnosticTimer?.cancel();
            _diagnosticTimer = null;
            updateUI(null);
          });
        });
      } else {
        _diagnosticTimer?.cancel();
        _diagnosticTimer = null;
        updateUI(null);
      }
    };

    subs.add(analysisServer.onActive.listen(handleActive));

    diagnostics.add([
      div()..add([
        span(text: 'contexts:', c: 'diagnostics-title'),
        contextCount = span(c: 'diagnostics-data')
      ]),
      div()..add([
        span(text: 'analyzed files:', c: 'diagnostics-title'),
        fileCount = span(c: 'diagnostics-data')
      ]),
      div()..add([
        span(text: 'task queue:', c: 'diagnostics-title'),
        taskQueueCount = span(c: 'diagnostics-data')
      ])
    ]);

    handleActive(analysisServer.isActive);
  }

  CoreElement _createAnalyticsSection(CoreElement container) {
    CoreElement section = container.add(div(c: 'view-section'));
    StatusHeader header = new StatusHeader(section);
    header.title.text = 'Google Analytics';

    CoreElement text = section.add(div(c: 'bottom-margin'));
    text.setInnerHtml(
      'The Dart plugin anonymously reports feature usage statistics and basic '
      'crash reports to improve the tool over time. See our privacy '
      '<a href="http://www.google.com/intl/en/policies/privacy/">policy</a>.'
    );

    CoreElement analyticsCheck = new CoreElement('input')
      ..element.attributes['type'] = 'checkbox';

    section.add([
      new CoreElement('label')..add([
        analyticsCheck,
        span(text: ' Enable analytics')
      ])
    ]);

    final String _key = '${pluginId}.sendUsage';
    InputElement check = analyticsCheck.element;
    check.checked = atom.config.getBoolValue(_key);
    check.onChange.listen((_) {
      atom.config.setValue(_key, check.checked);
    });
    subs.add(atom.config.onDidChange(_key).listen((_) {
      check.checked = atom.config.getBoolValue(_key);
    }));

    return section;
  }

  String get label => 'Plugin status';

  String get id => pluginId;

  void showSection(String sectionName) {
    CoreElement element = _sections[sectionName];

    if (element != null) {
      var e = element.element;
      e.scrollIntoView();
      e.classes.add('status-emphasis');
      new Timer(new Duration(milliseconds: 400), () {
        e.classes.remove('status-emphasis');
      });
    }
  }

  void handleClose() {
    super.handleClose();

    state[_statusOpenKey] = false;
  }

  void dispose() {
    _diagnosticTimer?.cancel();
    subs.cancel();
  }

  void _handleSdkBrowse() {
    atom.pickFolder().then((path) {
      if (path is String) {
        atom.config.setValue('${pluginId}.sdkLocation', path);
      }
    });
  }

  void _handleServerStart() {
    trackCommand('dartlang:analysis-server-start');
    analysisServer.start();
  }

  void _handleReanalyze() {
    trackCommand('dartlang:reanalyze-sources');
    analysisServer.reanalyzeSources();
  }

  void _handleServerStop() {
    trackCommand('dartlang:analysis-server-stop');
    analysisServer.shutdown();
  }

  static CoreElement _addButtons(ViewSection section) {
    return section.add(div(c: 'view-section-buttons'));
  }
}

class StatusHeader {
  CoreElement title;
  CoreElement subtitle;
  CoreElement toolbar;

  StatusHeader(CoreElement section) {
    section.add([
      div(c: 'status-header')..add([
        title = span(c: 'view-title'),
        subtitle = span(c: 'view-subtitle')..flex(),
        toolbar = span(c: 'view-subtitle')
      ])
    ]);
  }
}

/// 'Atom 1.0.11, dartlang 0.4.3'
Future<String> _getPlatformVersions() {
  return atomPackage.getPackageVersion().then((pluginVer) {
    String atomVer = atom.getVersion();
    return 'Atom ${atomVer}, ${pluginId} ${pluginVer}';
  });
}
