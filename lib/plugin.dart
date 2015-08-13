// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.plugin;

import 'dart:async';
import 'dart:js';

import 'package:logging/logging.dart';

import 'analysis/analysis_options.dart';
import 'analysis/dartdoc.dart';
import 'analysis/declaration_nav.dart';
import 'analysis/formatting.dart';
import 'analysis/organize_file.dart';
import 'analysis/quick_fixes.dart';
import 'analysis/refactor.dart';
import 'analysis/references.dart';
import 'analysis/type_hierarchy.dart';
import 'analysis_server.dart';
import 'atom.dart';
import 'atom_linter.dart' show LinterService;
import 'atom_statusbar.dart';
import 'atom_utils.dart';
import 'autocomplete.dart';
import 'buffer/buffer_observer.dart';
import 'dependencies.dart';
import 'editors.dart';
import 'error_repository.dart';
import 'impl/changelog.dart';
import 'impl/editing.dart' as editing;
import 'impl/pub.dart';
import 'impl/rebuild.dart';
import 'impl/smoketest.dart';
import 'impl/status_display.dart';
import 'linter.dart' show DartLinterConsumer;
import 'projects.dart';
import 'sdk.dart';
import 'sky/create_project.dart';
import 'sky/toolbar.dart';
import 'state.dart';
import 'usage.dart' show UsageManager;
import 'utils.dart';

export 'atom.dart' show registerPackage;

final Logger _logger = new Logger('plugin');

class AtomDartPackage extends AtomPackage {
  final Disposables disposables = new Disposables();
  final StreamSubscriptions subscriptions = new StreamSubscriptions();

  AtomDartPackage() {
    // Register a method to consume the `status-bar` service API.
    registerServiceConsumer('consumeStatusBar', (obj) {
      StatusDisplay status = new StatusDisplay(new StatusBar(obj));
      disposables.add(status);
      return status;
    });

    // Register a method to consume the `atom-toolbar` service API.
    registerServiceConsumer('consumeToolbar', (obj) {
      ToolbarContribution toolbar = new ToolbarContribution(new Toolbar(obj));
      disposables.add(toolbar);
      return toolbar;
    });

    // Register a method to consume the `linter-plus-self` service API.
    registerServiceConsumer('consumeLinter', (obj) {
      // This hoopla allows us to construct an object with Disposable
      // and return it without having to create a new class that
      // just does the same thing, but in another file.
      var errorController = new StreamController.broadcast();
      var flushController = new StreamController.broadcast();
      // TODO: expose analysis domain streams to avoid indirections
      errorRepository.initStreams(errorController.stream, flushController.stream);
      var consumer = new DartLinterConsumer(errorRepository);
      consumer.consume(new LinterService(obj));

      // Proxy error messages from analysis server to ErrorRepository when the
      // analysis server becomes active.
      analysisServer.isActiveProperty.where((active) => active).listen((_) {
        analysisServer.onAnalysisErrors.listen(errorController.add);
        analysisServer.onAnalysisFlushResults.listen(flushController.add);
      });

      return consumer;
    });

    var dartProvider = new DartAutocompleteProvider();
    // TODO: why isn't this working?
    // registerServiceProvider('provideAutocomplete', () => provider.toProxy());
    final JsObject exports = context['module']['exports'];
    exports['provideAutocomplete'] = () => dartProvider.toProxy();
  }

  void packageActivated([Map inState]) {
    _setupLogging();
    _logger.info("activated");

    if (deps == null) Dependencies.setGlobalInstance(new Dependencies());

    state.loadFrom(inState);
    checkChangelog();

    disposables.add(deps[SdkManager] = new SdkManager());
    disposables.add(deps[ProjectManager] = new ProjectManager());
    disposables.add(deps[AnalysisServer] = new AnalysisServer());
    disposables.add(deps[EditorManager] = new EditorManager());
    disposables.add(deps[ErrorRepository] = new ErrorRepository());

    AnalysisOptionsManager analysisOptionsManager = new AnalysisOptionsManager();
    PubManager pubManager = new PubManager();

    disposables.add(analysisOptionsManager);
    disposables.add(new CreateProjectManager());
    disposables.add(new DartdocHelper());
    disposables.add(new FormattingHelper());
    disposables.add(new NavigationHelper());
    disposables.add(new OrganizeFileManager());
    disposables.add(pubManager);
    disposables.add(new RefactoringHelper());
    disposables.add(new FindReferencesHelper());
    disposables.add(new TypeHierarchyHelper());
    disposables.add(new QuickFixHelper());

    disposables.add(new UsageManager());

    // Register commands.
    _addCmd('atom-workspace', 'dartlang:smoke-test-dev', (_) => smokeTest());
    _addCmd('atom-workspace', 'dartlang:rebuild-restart-dev', (_) {
      new RebuildJob().schedule();
    });
    _addCmd('atom-workspace', 'dartlang:auto-locate-sdk', (_) {
      new SdkLocationJob(sdkManager).schedule();
    });
    _addCmd('atom-workspace', 'dartlang:reanalyze-sources', (_) {
      new ProjectScanJob().schedule().then((_) {
        return new Future.delayed((new Duration(milliseconds: 100)));
      }).then((_) {
        if (analysisServer.isActive) {
          analysisServer.reanalyzeSources();
        } else {
          atom.notifications.addWarning('Analysis server not active.');
        }
      });
    });
    _addCmd('atom-workspace', 'dartlang:send-feedback', (_) {
      shell.openExternal('https://github.com/dart-atom/dartlang/issues');
    });

    // Text editor commands.
    _addCmd('atom-text-editor', 'dartlang:newline', editing.handleEnterKey);

    // Set up the context menus.
    List<ContextMenuItem> treeItems = [ContextMenuItem.separator];
    treeItems.addAll(pubManager.getTreeViewContributions());
    treeItems.addAll(analysisOptionsManager.getTreeViewContributions());
    treeItems.add(ContextMenuItem.separator);
    disposables.add(atom.contextMenu.add('.tree-view', treeItems));

    // Observe all buffers and send updates to analysis server
    disposables.add(new BufferObserverManager());

    Timer.run(_initPlugin);
  }

  void _initPlugin() {
    loadPackageJson().then(_verifyPackages);
  }

  // Verify that our dependencies are satisfied.
  void _verifyPackages(Map m) {
    List<String> deps = m['packages'];
    if (deps == null) deps = [];

    List<String> packages = atom.packages.getAvailablePackageNames();

    for (String dep in deps) {
      if (!packages.contains(dep)) {
        atom.notifications.addWarning(
          "The 'dartlang' plugin requires the '${dep}' plugin in order to work. "
          "You can install it via the Install section of the Settings dialog.",
          dismissable: true);
      }
    }

    if (packages.contains('emmet') && !atom.packages.isPackageDisabled('emmet')) {
      if (state['emmet'] == null) {
        state['emmet'] = true;

        atom.notifications.addWarning(
          "The emmet package has severe performance issues when editing Dart "
          "files. It is recommended to disable emmet until issue "
          "https://github.com/emmetio/emmet-atom/issues/319 is fixed.",
          dismissable: true);
      }
    }
  }

  Map serialize() => state.toMap();

  void packageDeactivated() {
    _logger.info('deactivated');
    disposables.dispose();
    subscriptions.cancel();

    // TODO: Cancel any running Jobs (see #120).

  }

  Map config() {
    return {
      // sdk
      'sdkLocation': {
        'title': 'Dart SDK Location',
        'description': 'The location of the Dart SDK.',
        'type': 'string',
        'default': '',
        'order': 1
      },

      // show infos and todos
      'showInfos': {
        'title': 'Show infos',
        'description': 'Show informational level analysis issues.',
        'type': 'boolean',
        'default': true,
        'order': 2
      },
      'showTodos': {
        'title': 'Show todos',
        'description': 'When showing infos, also show TODO items.',
        'type': 'boolean',
        'default': false,
        'order': 2
      },

      // format on save
      'formatOnSave': {
        'title': 'Format current file on save',
        'description': 'Format the current editor on save.',
        'type': 'boolean',
        'default': false,
        'order': 3
      },

      // filter specific warnings
      'filterUnnamedLibraryWarnings': {
        'title': 'Filter unnamed library warnings',
        'description': "Don't display warnings about unnamed libraries.",
        'type': 'boolean',
        'default': true,
        'order': 4
      },
      'filterCompiledToJSWarnings': {
        'title': 'Filter warnings about compiling to JavaScript',
        'description': "Don't display warnings about compiling to JavaScript.",
        'type': 'boolean',
        'default': true,
        'order': 4
      },

      // google analytics
      'sendUsageInformation': {
        'title': 'Report usage information to Google Analytics.',
        'description': "Report anonymized usage information to Google Analytics.",
        'type': 'boolean',
        'default': true,
        'order': 5
      },

      'logging': {
        'title': 'Log plugin diagnostics to the devtools console.',
        'description': 'This is for plugin development only!',
        'type': 'string',
        'default': 'info',
        'enum': ['error', 'warning', 'info', 'fine', 'finer'],
        'order': 10
      },
      'debugAnalysisServer': {
        'title': 'Start the analysis server with debug flags.',
        'description': 'This is for plugin development only! The analysis server '
            'will be started with the observatory port and AS diagnostics ports '
            'turned on. Restart required.',
        'type': 'boolean',
        'default': false,
        'order': 11
      }
    };
  }

  void _addCmd(String target, String command, void callback(AtomEvent e)) {
    disposables.add(atom.commands.add(target, command, callback));
  }

  void _setupLogging() {
    disposables.add(atom.config.observe('${pluginId}.logging', null, (val) {
      if (val == null) return;

      for (Level level in Level.LEVELS) {
        if (val.toUpperCase() == level.name) {
          Logger.root.level = level;
          break;
        }
      }

      _logger.info("logging level: ${Logger.root.level}");
    }));
  }
}
