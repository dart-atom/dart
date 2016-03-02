// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.plugin;

import 'dart:async';
import 'dart:js';

import 'package:atom/node/process.dart';
import 'package:atom/node/shell.dart';
import 'package:atom_dartlang/impl/tooltip.dart';
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
import 'atom_autocomplete.dart' show AutocompleteProvider;
import 'atom_linter.dart' show LinterService;
import 'atom_package_deps.dart' as package_deps;
import 'atom_statusbar.dart';
import 'atom_utils.dart';
import 'autocomplete.dart';
import 'buffer/buffer_observer.dart';
import 'dartino/dartino_util.dart' show dartino;
import 'dartino/launch_dartino.dart';
import 'debug/breakpoints.dart';
import 'debug/debugger.dart';
import 'dependencies.dart';
import 'editors.dart';
import 'error_repository.dart';
import 'flutter/flutter_daemon.dart';
import 'flutter/flutter_devices.dart';
import 'flutter/flutter_launch.dart';
import 'flutter/flutter_sdk.dart';
import 'flutter/flutter_tools.dart';
import 'flutter/mojo_launch.dart';
import 'impl/changelog.dart';
import 'impl/editing.dart' as editing;
import 'impl/errors.dart';
import 'impl/navigation.dart';
import 'impl/outline.dart';
import 'impl/pub.dart';
import 'impl/rebuild.dart';
import 'impl/status.dart';
import 'impl/status_display.dart';
import 'impl/tests.dart';
import 'impl/toolbar.dart';
import 'impl/toolbar_impl.dart';
import 'jobs.dart';
import 'js.dart';
import 'launch/console.dart';
import 'launch/launch.dart';
import 'launch/launch_cli.dart';
import 'launch/launch_configs.dart';
import 'launch/launch_shell.dart';
import 'launch/run.dart';
import 'linter.dart' show DartLinterConsumer;
import 'projects.dart';
import 'sdk.dart';
import 'state.dart';
import 'usage.dart' show UsageManager;
import 'utils.dart';
import 'views.dart';
import 'views.dart' show ViewGroupManager;

export 'atom.dart' show registerPackage;

final Logger _logger = new Logger('plugin');

class AtomDartPackage extends AtomPackage {
  final Disposables disposables = new Disposables(catchExceptions: true);
  final StreamSubscriptions subscriptions = new StreamSubscriptions(catchExceptions: true);

  ErrorsController errorsController;
  ConsoleController consoleController;
  DartLinterConsumer _consumer;

  AtomDartPackage() {
    // Register a method to consume the `status-bar` service API.
    registerServiceConsumer('consumeStatusBar', (JsObject obj) {
      StatusBar statusBar = new StatusBar(obj);

      if (errorsController != null) errorsController.initStatusBar(statusBar);
      if (consoleController != null) consoleController.initStatusBar(statusBar);

      StatusDisplay statusDisplay = new StatusDisplay(statusBar);
      disposables.add(statusDisplay);
      return statusDisplay;
    });

    // Register a method to consume the `atom-toolbar` service API.
    registerServiceConsumer('consumeToolbar', (JsObject obj) {
      DartToolbarContribution toolbar = new DartToolbarContribution(new Toolbar(obj));
      disposables.add(toolbar);
      return toolbar;
    });

    // Register a method to consume the `linter-plus-self` service API.
    registerServiceConsumer('consumeLinter', (JsObject obj) {
      _consumer.consume(new LinterService(obj));
      return _consumer;
    });

    final JsObject moduleExports = context['module']['exports'];
    AutocompleteProvider dartCompleterProvider = new DartAutocompleteProvider();
    moduleExports['provideAutocomplete'] = () => dartCompleterProvider.toProxy();
  }

  void packageActivated([dynamic pluginState]) {
    _setupLogging();

    _logger.info("activated");
    _logger.fine("Running on Chrome version ${process.chromeVersion}.");

    if (deps == null) Dependencies.setGlobalInstance(new Dependencies());

    state.loadFrom(pluginState);

    checkChangelog();

    disposables.add(deps[JobManager] = new JobManager());
    disposables.add(deps[SdkManager] = new SdkManager());
    disposables.add(deps[ProjectManager] = new ProjectManager());
    disposables.add(deps[AnalysisServer] = new AnalysisServer());
    disposables.add(deps[EditorManager] = new EditorManager());
    disposables.add(deps[ErrorRepository] = new ErrorRepository());
    disposables.add(deps[LaunchManager] = new LaunchManager());
    disposables.add(deps[LaunchConfigurationManager] = new LaunchConfigurationManager());
    disposables.add(deps[ProjectLaunchManager] = new ProjectLaunchManager());
    disposables.add(deps[BreakpointManager] = new BreakpointManager());
    disposables.add(deps[DebugManager] = new DebugManager());
    disposables.add(deps[ViewGroupManager] = new ViewGroupManager());
    disposables.add(deps[NavigationManager] = new NavigationManager());

    AnalysisOptionsManager analysisOptionsManager = new AnalysisOptionsManager();
    PubManager pubManager = new PubManager();

    RunApplicationManager runAppManager = new RunApplicationManager();
    disposables.add(deps[RunApplicationManager] = runAppManager);

    disposables.add(analysisOptionsManager);
    disposables.add(new ChangelogManager());
    disposables.add(deps[StatusViewManager] = new StatusViewManager());
    disposables.add(new FlutterToolsManager());
    disposables.add(new DartdocHelper());
    disposables.add(errorsController = new ErrorsController());
    disposables.add(new FormattingHelper());
    disposables.add(new NavigationHelper());
    disposables.add(new OrganizeFileManager());
    disposables.add(new OutlineController());
    disposables.add(new TooltipController());
    disposables.add(pubManager);
    disposables.add(runAppManager);
    disposables.add(new RefactoringHelper());
    disposables.add(new FindReferencesHelper());
    disposables.add(new TypeHierarchyHelper());
    disposables.add(deps[QuickFixHelper] = new QuickFixHelper());
    disposables.add(consoleController = new ConsoleController());
    disposables.add(deps[TestManager] = new TestManager());

    disposables.add(deps[FlutterSdkManager] = new FlutterSdkManager());
    disposables.add(deps[FlutterDaemonManager] = new FlutterDaemonManager());
    disposables.add(deps[FlutterDeviceManager] = new FlutterDeviceManager());

    disposables.add(new UsageManager());
    disposables.add(new RebuildManager());

    _registerLinter();
    _registerLaunchTypes();

    // Register commands.
    //_addCmd('atom-workspace', 'dartlang:smoke-test-dev', (_) => smokeTest());
    _addCmd('atom-workspace', 'dartlang:settings', (_) {
      atom.workspace.open('atom://config/packages/dartlang');
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
    _addCmd('atom-workspace', 'dartlang:send-feedback', (_) => _handleSendFeedback());
    _addCmd('atom-workspace', 'dartino:install-sdk', dartino.promptInstallSdk);
    _addCmd('atom-workspace', 'dartino:validate-sdk', dartino.validateSdk);

    // Text editor commands.
    _addCmd('atom-text-editor', 'dartlang:newline', editing.handleEnterKey);

    // Set up the context menus.
    List<ContextMenuItem> treeItems = [ContextMenuItem.separator];
    treeItems.addAll(runAppManager.getTreeViewContributions());
    treeItems.addAll(pubManager.getTreeViewContributions());
    treeItems.addAll(analysisOptionsManager.getTreeViewContributions());
    treeItems.addAll(projectManager.getTreeViewContributions());
    treeItems.add(ContextMenuItem.separator);
    disposables.add(atom.contextMenu.add('.tree-view', treeItems));

    // Observe all buffers and send updates to analysis server
    disposables.add(new BufferObserverManager());

    Timer.run(_initPlugin);
  }

  void _initPlugin() {
    // Install the packages we're dependent on.
    package_deps.install();

    loadPackageJson().then(_verifyPackages);

    _validateSettings();
  }

  // Set up default settings.
  void _validateSettings() {
    var runOnce = (String name, Function fn) {
      if (!atom.config.getBoolValue('_${pluginId}.${name}')) {
        atom.config.setValue('_${pluginId}.${name}', true);

        fn();
      }
    };

    runOnce('_firstRun', () {
      // Show a welcome toast.
      _showFirstRun();

      atom.config.setValue('autocomplete-plus.autoActivationDelay', 500);
      atom.config.setValue('core.followSymlinks', false);
    });
  }

  // Verify that our dependencies are satisfied.
  void _verifyPackages(Map m) {
    List<String> packages = atom.packages.getAvailablePackageNames();

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

  void _showFirstRun() => statusViewManager.toggleView();

  void _handleSendFeedback() {
    getSystemDescription().then((String description) {
      shell.openExternal('https://github.com/dart-atom/dartlang/issues/new?'
          'body=${Uri.encodeComponent(description)}');
    });
  }

  dynamic serialize() => state.saveState();

  void packageDeactivated() {
    _logger.info('deactivated');

    disposables.dispose();
    subscriptions.cancel();
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

      // custom views
      'useErrorsView': {
        'title': 'Show errors view',
        'description': 'Use a custom errors view to display Dart errors and '
            'warnings. This will be used in place of the default linter view.',
        'type': 'boolean',
        'default': true,
        'order': 3
      },
      'showOutlineView': {
        'title': 'Show outline view',
        'description': 'Show an outline view for Dart files.',
        'type': 'boolean',
        'default': true,
        'order': 3
      },

      // // auto show console
      // 'autoShowConsole': {
      //   'title': 'Auto open console',
      //   'description': 'Automatically open the console when an application is run.',
      //   'type': 'boolean',
      //   'default': true,
      //   'order': 4
      // },

      // show infos and todos
      'showInfos': {
        'title': 'Show infos',
        'description': 'Show informational level analysis issues.',
        'type': 'boolean',
        'default': true,
        'order': 5
      },
      'showTodos': {
        'title': 'Show todos',
        'description': 'When showing infos, also show TODO items.',
        'type': 'boolean',
        'default': false,
        'order': 5
      },

      // format on save
      'formatOnSave': {
        'title': 'Format current file on save',
        'description': 'Format the current editor on save.',
        'type': 'boolean',
        'default': false,
        'order': 6
      },

      // key-bindings
      'jumpToDeclarationKeys': {
        'title': 'Jump to declaration modifer key',
        'description': 'The modifer key to use when clicking on a symbol in '
            'order to jump to is declaration.',
        'type': 'string',
        'default': isMac ? 'command' : 'control',
        'enum': isMac ? ['command', 'option'] : ['control', 'alt'],
        'order': 7
      },

      // no package symlinks
      'noPackageSymlinks': {
        'title': "Run pub with '--no-package-symlinks'",
        'description':
            'Run pub with a command-line option to not create packages '
            'symlinks. Note: Flutter applications will not currently work with '
            'this option enabled.',
        'type': 'boolean',
        'default': false,
        'order': 8
      },

      // google analytics
      'sendUsage': {
        'title': 'Report usage information to Google Analytics.',
        'description': "Report anonymized usage information to Google Analytics.",
        'type': 'boolean',
        'default': true,
        'order': 9
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
        'description':
          'Start the analysis server with its diagnostics port enabled. A '
          'restart is required.',
        'type': 'boolean',
        'default': false,
        'order': 11
      },

      // experimental features
      'hoverTooltip': {
        'title': '[Experimental] Enable type information tooltip.',
        'type': 'boolean',
        'default': false,
        'order': 12
      }
    };
  }

  void _addCmd(String target, String command, void callback(AtomEvent e)) {
    disposables.add(atom.commands.add(target, command, callback));
  }

  void _registerLaunchTypes() {
    FlutterLaunchType.register(launchManager);
    DartinoLaunchType.register(launchManager);
    CliLaunchType.register(launchManager);
    MojoLaunchType.register(launchManager);
    ShellLaunchType.register(launchManager);
    //WebLaunchType.register(launchManager);
  }

  void _registerLinter() {
    // This hoopla allows us to construct an object with Disposable and return
    // it without having to create a new class that just does the same thing,
    // but in another file.
    var errorController = new StreamController<AnalysisErrors>.broadcast();
    var flushController = new StreamController<AnalysisFlushResults>.broadcast();
    errorRepository.initStreams(errorController.stream, flushController.stream);
    _consumer = new DartLinterConsumer(errorRepository);
    deps[DartLinterConsumer] = _consumer;

    // Proxy error messages from analysis server to ErrorRepository when the
    // analysis server becomes active.
    var registerListeners = () {
      analysisServer.onAnalysisErrors.listen(errorController.add);
      analysisServer.onAnalysisFlushResults.listen(flushController.add);
    };

    if (analysisServer.isActive) registerListeners();
    analysisServer.onActive.where((active) => active).listen((_) {
      registerListeners();
    });
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
