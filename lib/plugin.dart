// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.plugin;

import 'dart:async';
import 'dart:js';

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/package.dart';
import 'package:atom/node/process.dart';
import 'package:atom/node/shell.dart';
import 'package:atom/utils/dependencies.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import 'analysis/analysis_options.dart';
import 'analysis/buffer_observer.dart';
import 'analysis/completions.dart';
import 'analysis/dartdoc.dart';
import 'analysis/declaration_nav.dart';
import 'analysis/find_type.dart';
import 'analysis/formatting.dart';
import 'analysis/organize_file.dart';
import 'analysis/quick_fixes.dart';
import 'analysis/refactor.dart';
import 'analysis/references.dart';
import 'analysis/type_hierarchy.dart';
import 'analysis_server.dart';
import 'atom_autocomplete.dart' show AutocompleteProvider;
import 'atom_linter.dart' show LinterService;
import 'atom_package_deps.dart' as package_deps;
import 'atom_statusbar.dart';
import 'atom_utils.dart';
import 'dartino/dartino.dart' show dartino;
import 'debug/breakpoints.dart';
import 'debug/debugger.dart';
import 'editors.dart';
import 'error_repository.dart';
import 'flutter/flutter.dart';
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
import 'impl/testing.dart';
import 'impl/toolbar.dart';
import 'impl/toolbar_impl.dart';
import 'jobs.dart';
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
import 'views.dart';
import 'views.dart' show ViewGroupManager;

final Logger _logger = new Logger('plugin');

String pluginVersion;

class AtomDartPackage extends AtomPackage {
  final Disposables disposables = new Disposables(catchExceptions: true);
  final StreamSubscriptions subscriptions = new StreamSubscriptions(catchExceptions: true);

  ErrorsController errorsController;
  ConsoleController consoleController;
  DartLinterConsumer _consumer;

  AtomDartPackage() : super(pluginId) {
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

  void activate([dynamic pluginState]) {
    _setupLogging();

    _logger.info("activated");
    _logger.fine("Running on Chrome version ${process.chromeVersion}.");

    if (deps == null) Dependencies.setGlobalInstance(new Dependencies());

    state.loadFrom(pluginState);

    checkChangelog();
    atomPackage.getPackageVersion().then((String version) {
      pluginVersion = version;
    });

    Flutter.setMinSdkVersion();
    disposables.add(dartino);

    disposables.add(deps[JobManager] = new JobManager());
    disposables.add(deps[SdkManager] = new SdkManager());
    disposables.add(deps[ProjectManager] = new ProjectManager());
    disposables.add(deps[AnalysisServer] = new AnalysisServer());
    disposables.add(deps[EditorManager] = new EditorManager());
    disposables.add(deps[ErrorRepository] = new ErrorRepository());
    disposables.add(deps[LaunchManager] = new LaunchManager());
    disposables.add(deps[LaunchConfigurationManager] = new LaunchConfigurationManager());
    disposables.add(deps[WorkspaceLaunchManager] = new WorkspaceLaunchManager());
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
    disposables.add(new FormattingManager());
    disposables.add(new NavigationHelper());
    disposables.add(new OrganizeFileManager());
    disposables.add(new OutlineController());
    disposables.add(pubManager);
    disposables.add(runAppManager);
    disposables.add(new RefactoringHelper());
    disposables.add(new FindReferencesHelper());
    disposables.add(new FindTypeHelper());
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
      atom.workspace.openConfigPage(packageID: 'dartlang');
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
    // Always register this one Flutter command so that Flutter will be
    // properly activated/enabled when/if the Flutter plugin is installed
    // in a running system.
    _addCmd('atom-workspace', 'flutter:enable', flutter.enable);
    // Always register this one Dartino command so that Dartino will be
    // properly activated/enabled when/if the Dartino plugin is installed
    // in a running system.
    _addCmd('atom-workspace', 'dartino:enable', dartino.enable);
    _addCmd('atom-workspace', 'dartlang:send-feedback', (_) => _handleSendFeedback());

    // Text editor commands.
    _addCmd('atom-text-editor', 'dartlang:newline', editing.handleEnterKey);

    // Set up the context menus.
    List<ContextMenuItem> treeItems = [ContextMenuItem.separator];
    treeItems.addAll(runAppManager.getTreeViewContributions());
    treeItems.addAll(pubManager.getTreeViewContributions());
    treeItems.addAll(analysisOptionsManager.getTreeViewContributions());
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

  void deactivate() {
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
      'showOutlineView': {
        'title': 'Show outline view',
        'description': 'Show the outline view for Dart files.',
        'type': 'boolean',
        'default': true,
        'order': 3
      },

      'showErrorsView': {
        'title': 'Show errors view',
        'description': 'Show the error and warnings view.',
        'type': 'boolean',
        'default': true,
        'order': 4
      },

      // show infos and todos
      'configureErrorsView': {
        'title': "Errors view configuration",
        'description': 'Choose which types of items to show in the errors view.',
        'type': 'string',
        'default': 'infos',
        'enum': ['errors+warnings', 'infos', 'todos'],
        'order': 5
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

      // debugger
      'debuggerCaughtExceptions': {
        'title': "Debugger break on exceptions mode",
        'description': 'Break on all exceptions, uncaught exceptions, or ignore exceptions.',
        'type': 'string',
        'default': 'uncaught',
        'enum': ['all', 'uncaught', 'none'],
        'order': 8
      },

      // google analytics
      'sendUsage': {
        'title': 'Report usage information to Google Analytics',
        'description': "Report anonymized usage information to Google Analytics.",
        'type': 'boolean',
        'default': true,
        'order': 10
      },

      'logging': {
        'title': '[Diagnostics] Log plugin diagnostics to the DevTools console',
        'type': 'string',
        'default': 'info',
        'enum': ['error', 'warning', 'info', 'fine', 'finer'],
        'order': 11
      },
      'debugAnalysisServer': {
        'title': '[Diagnostics] Start the analysis server with debug flags',
        'description': 'Start the analysis server with its diagnostics port enabled '
          '(at localhost:23072); a restart is required.',
        'type': 'boolean',
        'default': false,
        'order': 12
      },

      // experimental features
      // TODO(devoncarew): This option needs some debugging; see #931.
      'formatOnSave': {
        'title': '[Experimental] Format files on save',
        'description': 'Format the current editor on save. Note: this does not work well with Atom\'s autosave feature.',
        'type': 'boolean',
        'default': false,
        'order': 13
      }
    };
  }

  void _addCmd(String target, String command, void callback(AtomEvent e)) {
    disposables.add(atom.commands.add(target, command, callback));
  }

  void _registerLaunchTypes() {
    if (Flutter.hasFlutterPlugin()) {
      FlutterLaunchType.register(launchManager);
      MojoLaunchType.register(launchManager);
    }
    CliLaunchType.register(launchManager);
    ShellLaunchType.register(launchManager);
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
