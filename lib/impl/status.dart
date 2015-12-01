import 'dart:async';
import 'dart:html' show InputElement;

import '../atom.dart';
import '../atom_utils.dart';
import '../elements.dart';
import '../material.dart';
import '../sdk.dart';
import '../state.dart';
import '../usage.dart' show trackCommand;
import '../utils.dart';
import '../views.dart';

final String _statusOpenKey = 'statusOpen';

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
      link.onClick.listen((_) => shell.openExternal(link.href));
    }

    _sections[sectionId] = element;

    return element;
  }

  CoreElement _createPluginSection(CoreElement container) {
    CoreElement section = container.add(div(c: 'view-section'));
    StatusHeader header = new StatusHeader(section);
    header.title.text = '${pluginId} plugin';
    getPackageVersion().then((str) {
      header.subtitle.text = str;
    });

    header.toolbar.add(new MIconButton('icon-tools')..click(() {
      atom.workspace.open('atom://config/packages/dartlang');
    }))..tooltip = 'Settings';

    CoreElement text = section.add(div());
    text.setInnerHtml(
      'For help using this plugin, please see our getting started '
      '<a href="https://dart-atom.github.io/dartlang/">guide</a>. '
      'Please file feature requests and bugs on the '
      '<a href="https://github.com/dart-atom/dartlang/issues">issue tracker</a>.'
    );

    CoreElement buttons = _addButtons(section);
    buttons.add(button(text: 'Check for Updates', c: 'btn')..click(() {
      atom.workspace.open('atom://config/updates');
    }));
    buttons.add(button(text: 'Feedback…', c: 'btn')..click(() {
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

  // TODO: diagnostics page; enable diagnostics port; graphs

  ViewSection _createAnalysisServerSection(CoreElement container) {
    CoreElement section = container.add(div(c: 'view-section'));
    StatusHeader header = new StatusHeader(section);
    CoreElement start;
    CoreElement reanalyze;
    CoreElement stop;

    header.title.text = 'Analysis server';
    String version;

    var update = ([_]) {
      start.disabled = analysisServer.isActive;
      reanalyze.enabled = analysisServer.isActive;
      stop.enabled = analysisServer.isActive;

      if (!analysisServer.isActive) {
        header.subtitle.text = '';
        header.toolbar.text = 'not active';
      } else {
        header.toolbar.text = analysisServer.isBusy ? 'analyzing…' : 'idle';

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
    final Duration _duration = new Duration(seconds: 3);

    Strobe commandStrobe;
    CoreElement command;
    Timer commandTimer;

    Strobe responseStrobe;
    CoreElement response;
    Timer responseTimer;

    section.add([
      div(c: 'overflow-hidden-ellipsis')..add([
        commandStrobe = new Strobe(classes: 'icon-triangle-right'),
        command = span(c: 'text-subtle')
      ]),
      div(c: 'overflow-hidden-ellipsis bottom-margin')..add([
        responseStrobe = new Strobe(classes: 'icon-triangle-left'),
        response = span(c: 'text-subtle overflow-hidden-ellipsis')
      ])
    ]);

    subs.add(analysisServer.onSend.listen((str) {
      commandStrobe.strobe();
      command.text = str;
      commandTimer?.cancel();
      commandTimer = new Timer(_duration, () => command.text = '');
    }));
    subs.add(analysisServer.onReceive.listen((str) {
      responseStrobe.strobe();
      response.text = str;
      responseTimer?.cancel();
      responseTimer = new Timer(_duration, () => response.text = '');
    }));

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

  CoreElement _createAnalyticsSection(CoreElement container) {
    CoreElement section = container.add(div(c: 'view-section'));
    StatusHeader header = new StatusHeader(section);
    header.title.text = 'Google Analytics';

    CoreElement text = section.add(div(c: 'bottom-margin'));
    text.text =
      "The Dart plugin anonymously reports feature usage statistics and basic "
      "crash reports to improve the tool over time. See our privacy "
      "<a href='http://www.google.com/intl/en/policies/privacy/'>policy</a>.";

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

  String get label => 'Dart plugin status';

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
  return getPackageVersion().then((pluginVer) {
    String atomVer = atom.getVersion();
    return 'Atom ${atomVer}, ${pluginId} ${pluginVer}';
  });
}

// TODO: old diagnostics code

// void _showDiagnostics() {
//   if (!isActive) {
//     atom.notifications.addWarning('Analysis server not running.');
//     return;
//   }
//
//   _server.diagnostic.getDiagnostics().then((DiagnosticsResult diagnostics) {
//     List<ContextData> contexts = diagnostics.contexts;
//
//     String info = '${contexts.length} ${pluralize('context', contexts.length)}\n\n';
//     info = info + contexts.map((ContextData context) {
//       int fileCount = context.explicitFileCount + context.implicitFileCount;
//       List<String> exceptions = context.cacheEntryExceptions ?? [];
//
//       return ('${context.name}\n'
//         '  ${fileCount} total analyzed files (${context.explicitFileCount} explicit), '
//         'queue length ${context.workItemQueueLength}\n  '
//         + exceptions.join('\n  ')
//       ).trim();
//     }).join('\n\n');
//
//     atom.notifications.addInfo(
//       'Analysis server diagnostics',
//       detail: info,
//       dismissable: true
//     );
//   }).catchError((e) {
//     if (e is RequestError) {
//       atom.notifications.addError(
//         'Diagnostics Error',
//         description: '${e.code} ${e.message}',
//         dismissable: true
//       );
//     } else {
//       atom.notifications.addError(
//         'Diagnostics Error',
//         description: '${e}',
//         dismissable: true
//       );
//     }
//   });
// }
