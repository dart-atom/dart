// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.plugin;

import 'dart:async';

import 'package:logging/logging.dart';

import 'analysis_server.dart';
import 'atom.dart';
import 'atom_autocomplete.dart';
import 'atom_statusbar.dart';
import 'dependencies.dart';
import 'editors.dart';
import 'projects.dart';
import 'sdk.dart';
import 'state.dart';
import 'utils.dart';
import 'impl/editing.dart' as editing;
import 'impl/pub.dart';
import 'impl/rebuild.dart';
import 'impl/smoketest.dart';
import 'impl/status_display.dart';
import 'linter.dart' show DartLinterConsumer;
import 'atom_linter.dart' show LinterService;
import 'error_repository.dart';

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

    // Register a method to consume the `linter-plus-self` service API
    registerServiceConsumer('consumeLinter', (obj) {
      // This hoopla allows us to construct an object with Disposable
      // and return it without having to create a new class that
      // just does the same thing, but in another file.
      var sc = new StreamController.broadcast();
      var errorStream = sc.stream;
      var consumer = new DartLinterConsumer(new ErrorRepository(errorStream));
      consumer.consume(new LinterService(obj));

      // Proxy error messages from analysis server to ErrorRepository when
      // the analysis server becomes active.
      analysisServer.isActiveProperty.where((active) => active).listen((_) {
        analysisServer.onAnalysisErrors.listen(sc.add);
      });

      return consumer;
    });
  }

  void packageActivated([Map state]) {
    _setupLogging();

    _logger.fine("packageActivated");

    if (deps == null) Dependencies.setGlobalInstance(new Dependencies());

    disposables.add(deps[SdkManager] = new SdkManager());
    disposables.add(deps[ProjectManager] = new ProjectManager());
    disposables.add(deps[AnalysisServer] = new AnalysisServer());
    disposables.add(deps[EditorManager] = new EditorManager());

    // Register commands.
    _addCmd('atom-workspace', 'dart-lang-experimental:smoke-test', (_) => smokeTest());
    _addCmd('atom-workspace', 'dart-lang-experimental:rebuild-restart', (_) {
      new RebuildJob().schedule();
    });
    _addCmd('atom-workspace', 'dart-lang-experimental:auto-locate-sdk', (_) {
      new SdkLocationJob(sdkManager).schedule();
    });
    _addCmd('atom-workspace', 'dart-lang-experimental:refresh-dart-projects', (_) {
      new ProjectScanJob().schedule();
    });

    // Text editor commands.
    _addCmd('atom-text-editor', 'dart-lang-experimental:newline', editing.handleEnterKey);

    // Register commands that require an SDK to be present.
    _addSdkCmd('atom-text-editor', 'dart-lang-experimental:pub-get', (event) {
      new PubJob.get(dirname(event.editor.getPath())).schedule();
    });
    _addSdkCmd('atom-text-editor', 'dart-lang-experimental:pub-upgrade', (event) {
      new PubJob.upgrade(dirname(event.editor.getPath())).schedule();
    });
    _addSdkCmd('.tree-view', 'dart-lang-experimental:pub-get', (AtomEvent event) {
      new PubJob.get(dirname(event.selectedFilePath)).schedule();
    });
    _addSdkCmd('.tree-view', 'dart-lang-experimental:pub-upgrade', (event) {
      new PubJob.upgrade(dirname(event.selectedFilePath)).schedule();
    });

    // Register the autocomplete provider.
    //new DartAutocompleteProvider().register();
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

      _logger.fine("logging level: ${Logger.root.level}");
    }));
  }
}

// TODO: Move this class to a different file.
class DartAutocompleteProvider extends AutocompleteProvider {
  // inclusionPriority: 100, excludeLowerPriority: true, filterSuggestions: true
  DartAutocompleteProvider() : super('.source.dart');

  void register() => AutocompleteProvider.registerAutocompleteProvider(
      'provideAutocomplete', this);

  Future<List<Suggestion>> getSuggestions(AutocompleteOptions options) {
    List<Suggestion> suggestions = [
      new Suggestion(text: 'lorem'),
      new Suggestion(text: 'ipsum')
    ];

    return new Future.value(suggestions);
  }
}
