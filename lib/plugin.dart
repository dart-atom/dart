// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.plugin;

import 'dart:async';
import 'dart:js';

import 'package:logging/logging.dart';

import 'analysis_server.dart';
import 'autocomplete.dart';
import 'atom.dart';
import 'atom_linter.dart' show LinterService;
import 'atom_statusbar.dart';
import 'atom_utils.dart';
import 'buffer/buffer_updater.dart';
import 'dependencies.dart';
import 'editors.dart';
import 'error_repository.dart';
import 'linter.dart' show DartLinterConsumer;
import 'projects.dart';
import 'sdk.dart';
import 'state.dart';
import 'utils.dart';
import 'analysis/formatting.dart';
import 'analysis/navigation.dart';
import 'impl/editing.dart' as editing;
import 'impl/pub.dart';
import 'impl/rebuild.dart';
import 'impl/smoketest.dart';
import 'impl/status_display.dart';

export 'atom.dart' show registerPackage;

final Logger _logger = new Logger("atom-dart");

class AtomDartPackage extends AtomPackage {
  final Disposables disposables = new Disposables();
  final StreamSubscriptions subscriptions = new StreamSubscriptions();

  AtomDartPackage() {
    // Register a method to consume the `status-bar` service API.
    registerServiceConsumer('consumeStatusBar', (obj) {
      // Create a new status bar display.
      return new StatusDisplay(new StatusBar(obj));
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
    var provider = new DartAutocompleteProvider();
    // TODO: why isn't this working?
    // registerServiceProvider('provideAutocomplete',
    //   () => provider.toProxy());
    final JsObject exports = context['module']['exports'];
    exports['provideAutocomplete'] = () => provider.toProxy();
  }

  void packageActivated([Map state]) {
    _setupLogging();

    _logger.fine("packageActivated");

    if (deps == null) Dependencies.setGlobalInstance(new Dependencies());

    disposables.add(deps[SdkManager] = new SdkManager());
    disposables.add(deps[ProjectManager] = new ProjectManager());
    disposables.add(deps[AnalysisServer] = new AnalysisServer());
    disposables.add(deps[EditorManager] = new EditorManager());
    disposables.add(deps[ErrorRepository] = new ErrorRepository());
    disposables.add(new FormattingHelper());
    disposables.add(new NavigationHelper());

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
      }).then((_) => analysisServer.reanalyzeSources());
    });
    _addCmd('atom-workspace', 'dartlang:send-feedback', (_) {
      shell.openExternal('https://github.com/dart-atom/dartlang/issues');
    });

    // Text editor commands.
    _addCmd('atom-text-editor', 'dartlang:newline', editing.handleEnterKey);

    // Register commands that require an SDK to be present.
    _addSdkCmd('atom-text-editor', 'dartlang:pub-get', (event) {
      new PubJob.get(dirname(event.editor.getPath())).schedule();
    });
    _addSdkCmd('atom-text-editor', 'dartlang:pub-upgrade', (event) {
      new PubJob.upgrade(dirname(event.editor.getPath())).schedule();
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-get', (AtomEvent event) {
      new PubJob.get(dirname(event.selectedFilePath)).schedule();
    });
    _addSdkCmd('.tree-view', 'dartlang:pub-upgrade', (event) {
      new PubJob.upgrade(dirname(event.selectedFilePath)).schedule();
    });

    // Observe all buffers and send updates to analysis server
    disposables.add(new BufferUpdaterManager());
  }

  void packageDeactivated() {
    _logger.fine('packageDeactivated');
    disposables.dispose();
    subscriptions.cancel();
  }

  Map config() {
    return {
      'sdkLocation': {
        'title': 'Dart SDK Location',
        'description': 'The location of the Dart SDK.',
        'type': 'string',
        'default': ''
      },
      'showInfos': {
        'title': 'Show infos',
        'description': 'Show informational level analysis issues.',
        'type': 'boolean',
        'default': true
      },
      'showTodos': {
        'title': 'Show todos',
        'description': 'When showing infos, also show TODO items.',
        'type': 'boolean',
        'default': false
      },
      // These settings start with `x_` so they sort after the other settings in
      // our preferences dialog.
      'x_filterUnnamedLibraryWarnings': {
        'title': 'Filter unnamed library warnings',
        'description': "Don't display warnings about unnamed libraries.",
        'type': 'boolean',
        'default': true
      },
      'x_filterCompiledToJSWarnings': {
        'title': 'Filter warnings about compiling to JavaScript',
        'description': "Don't display warnings about compiling to JavaScript.",
        'type': 'boolean',
        'default': true
      }
    };
  }

  void _addCmd(String target, String command, void callback(AtomEvent e)) {
    disposables.add(atom.commands.add(target, command, callback));
  }

  // Validate that an sdk is available before calling the target function.
  void _addSdkCmd(String target, String command, void callback(AtomEvent e)) {
    disposables.add(atom.commands.add(target, command, (event) {
      if (!sdkManager.hasSdk) {
        sdkManager.showNoSdkMessage();
      } else {
        callback(event);
      }
    }));
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
