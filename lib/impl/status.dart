import 'dart:async';

import '../atom.dart';
import '../atom_utils.dart';
import '../elements.dart';
import '../sdk.dart';
import '../state.dart';
import '../usage.dart' show trackCommand;
import '../utils.dart';
import '../views.dart';

final String _statusOpenKey = 'statusOpen';

// TODO: scroll to a section and flash it

class StatusViewManager implements Disposable {
  Disposables disposables = new Disposables();

  StatusViewManager() {
    disposables.add(atom.commands.add('atom-workspace', '${pluginId}:show-plugin-status', (_) {
      toggleView();
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

    last = _createPluginSection(container);
    last = _createDartSdkSection(container);
    last = _createAnalysisServerSection(container);
    last = _createAnalyticsSection(container);

    last.toggleClass('view-section-last');

    state[_statusOpenKey] = true;
  }

  CoreElement _createPluginSection(CoreElement container) {
    CoreElement section = container.add(div(c: 'view-section'));
    StatusHeader header = new StatusHeader(section);
    header.title.text = '${pluginId} plugin';
    getPackageVersion().then((str) {
      header.subtitle.text = ' - ${str}';
    });

    CoreElement text = section.add(div());
    text.element.setInnerHtml(
      'For help using this plugin, please see our getting started '
      '<a href="https://dart-atom.github.io/dartlang/">guide</a>. '
      'Please file feature requests and bugs on the '
      '<a href="https://github.com/dart-atom/dartlang/issues">issue tracker</a>.',
      treeSanitizer: new TrustedHtmlTreeSanitizer()
    );
    for (var link in text.element.querySelectorAll('a')) {
      link.onClick.listen((_) => shell.openExternal(link.href));
    }

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
    text.element.setInnerHtml(
      'Visit <a>dartlang.org</a> for information on installing a Dart SDK for your platform.',
      treeSanitizer: new TrustedHtmlTreeSanitizer()
    );
    var link = text.element.querySelector('a');
    link.onClick.listen((_) {
      shell.openExternal('https://www.dartlang.org/downloads/');
    });

    var update = (Sdk sdk) {
      if (sdk == null) {
        header.subtitle.text = ' - no SDK configured';
        pathElement.text = '';
        pathElement.tooltip = '';
      } else {
        sdk.getVersion().then((ver) {
          header.subtitle.text = ' - ${ver}';
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
      // TODO: this needs to be more noisy on success
      sdkManager.tryToAutoConfigure();
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
        header.subtitle.text = ' - not active';
      } else {
        Future f = version != null
          ? new Future.value(version)
          : analysisServer.server.server.getVersion().then((v) => v.version);

        f.then((v) {
          version = v;

          String status = analysisServer.isBusy ? 'analyzing…' : 'idle';
          header.subtitle.text = ' - ${version}; ${status}';
        });
      }
    };

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

    CoreElement text = section.add(div());
    text.text =
      "The Dart plugin anonymously reports feature usage statistics and basic "
      "crash reports to improve the tool over time. Please visit the plugin's "
      "settings page to configure this behavior.";

    CoreElement buttons = _addButtons(section);
    buttons.add(button(text: 'Settings', c: 'btn')..click(() {
      atom.workspace.open('atom://config/packages/dartlang');
    }));

    return section;
  }

  String get label => 'Dart plugin status';

  String get id => pluginId;

  void showSection(String sectionName) {
    // TODO:

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

  StatusHeader(CoreElement section) {
    section.add([
      div(c: 'status-header')..add([
        title = span(c: 'view-title'),
        subtitle = span(c: 'view-subtitle')
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
