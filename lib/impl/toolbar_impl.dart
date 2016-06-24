
import 'dart:async';
import 'dart:html' show SelectElement;

import 'package:atom/atom.dart';
import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';

import '../elements.dart';
import '../flutter/flutter_devices.dart';
import '../launch/launch.dart';
import '../launch/run.dart';
import '../projects.dart';
import '../state.dart';
import 'testing.dart';
import 'toolbar.dart';

WorkspaceLaunchManager get _workspaceLaunchManager => deps[WorkspaceLaunchManager];

TestManager get testManager => deps[TestManager];

class DartToolbarContribution implements Disposable {
  ToolbarTile leftTile;
  ToolbarTile flutterTile;
  ToolbarTile rightTile;
  StreamSubscriptions subs = new StreamSubscriptions();

  DartToolbarContribution(Toolbar toolbar) {
    // Delay construction of the toolbar; the toolbar UI can be constructed before
    // all the global singeltons have been set up (like WorkspaceLaunchManager).
    Timer.run(() {
      leftTile = toolbar.addLeftTile(item: _buildLeftTile().element);
      flutterTile = toolbar.addLeftTile(item: _buildFlutterTile().element);
      rightTile = toolbar.addRightTile(item: _buildRightTile().element);
    });
  }

  CoreElement _buildLeftTile() {
    CoreElement runButton;
    CoreElement appSelectList;
    CoreElement configureLaunchButton;

    // `settings-view` class added to get proper styling for select elements.
    CoreElement e = div(c: 'btn-group btn-group dartlang-toolbar settings-view')..add([
      runButton = button(c: 'btn icon icon-playback-play')
        ..click(_handleRunLaunch)
        ..tooltip = "Run",
      // TODO: Add a stop button.
      configureLaunchButton = button(c: 'btn icon icon-gear')
        ..click(_handleConfigureLaunch)
        ..tooltip = 'Configure launch',
      appSelectList = new CoreElement('select', classes: 'form-control')
    ]);

    _bindLaunchManager(runButton, appSelectList, configureLaunchButton);

    return e;
  }

  CoreElement _buildFlutterTile() {
    CoreElement flutterDiv;
    CoreElement deviceList;
    CoreElement runModeList;

    // `settings-view` class added to get proper styling for select elements.
    CoreElement e = div(c: 'btn-group btn-group dartlang-toolbar settings-view')..add([
      flutterDiv = div(c: 'btn-group btn-group dartlang-toolbar')..add([
        div(c: 'icon icon-device-mobile')..id = 'toolbar-mobile-icon'
          ..tooltip = "Available devices",
        deviceList = new CoreElement('select', classes: 'form-control'),
        runModeList = new CoreElement('select', classes: 'form-control')
          ..element.style.width = '120px'
      ]),
    ]);

    // Bind the device pulldown.
    FlutterDeviceManager deviceManager = deps[FlutterDeviceManager];
    _bindDevicesToSelect(deviceManager, deviceList, runModeList);

    void updateToolbar() {
      String path = atom.workspace.getActiveTextEditor()?.getPath();
      DartProject project = projectManager.getProjectFor(path);

      bool isFlutterProject = project != null && project.isFlutterProject();
      bool isFlutterRunnable = _workspaceLaunchManager.selectedRunnable?.isFlutterRunnable ?? false;

      flutterDiv.hidden(!isFlutterProject && !isFlutterRunnable);
    }

    updateToolbar();

    subs.add(editorManager.dartProjectEditors.onActiveEditorChanged.listen((TextEditor editor) {
      updateToolbar();
    }));
    subs.add(projectManager.onProjectsChanged.listen((List<DartProject> projects) {
      updateToolbar();
    }));
    subs.add(_workspaceLaunchManager.onSelectedRunnableChanged.listen((RunnableConfig config) {
      updateToolbar();
    }));

    return e;
  }

  CoreElement _buildRightTile() {
    CoreElement runTestsDiv;
    CoreElement outlineToggleDiv;

    // `settings-view` class added to get proper styling for select elements.
    CoreElement e = div(c: 'settings-view', a: 'flex-center')..add([
      div(c: 'btn-group btn-group dartlang-toolbar')..add([
        div()..add([
          runTestsDiv = button(c: 'btn icon icon-pulse')
            ..click(_runTests)
            ..tooltip = "Run Tests"
            ..display = 'none'
        ]),
        div()..add([
          outlineToggleDiv = button(c: 'btn icon icon-list-unordered')
            ..click(_toggleOutline)
            ..tooltip = "Toggle Dart Outline View"
        ])
      ])
    ]);

    void updateToolbar() {
      String path = atom.workspace.getActiveTextEditor()?.getPath();

      runTestsDiv.display = testManager.isRunnableTest(path) ? 'inline-block' : 'none';
      outlineToggleDiv.enabled = isDartFile(path);
    }

    updateToolbar();
    subs.add(editorManager.dartProjectEditors.onActiveEditorChanged.listen((TextEditor editor) {
      updateToolbar();
    }));

    return e;
  }

  void _bindLaunchManager(
    CoreElement runButton,
    CoreElement selectList,
    CoreElement configureButton
  ) {
    SelectElement element = selectList.element as SelectElement;

    List<RunnableConfig> runnables = [];

    var updateUI = () {
      runnables = _workspaceLaunchManager.runnables;

      runButton.enabled = runnables.isNotEmpty;
      selectList.enabled = runnables.isNotEmpty;
      configureButton.enabled = runnables.isNotEmpty;

      selectList.clear();

      if (runnables.isEmpty) {
        selectList.add(new CoreElement('option')..text = 'No runnable apps');

      } else {
        runnables.sort();

        for (RunnableConfig runnable in runnables) {
          selectList.add(new CoreElement('option')..text = runnable.getDisplayName());
        }

        int index = runnables.indexOf(_workspaceLaunchManager.selectedRunnable);
        if (index != -1) {
          element.selectedIndex = index;
        }
      }
    };

    subs.add(_workspaceLaunchManager.onRunnablesChanged.listen((List<RunnableConfig> runnables) => updateUI()));
    subs.add(_workspaceLaunchManager.onSelectedRunnableChanged.listen((RunnableConfig runnable) => updateUI()));

    element.onChange.listen((e) {
      int index = element.selectedIndex;
      if (index >= 0 && index < runnables.length) {
        _workspaceLaunchManager.setSelectedRunnable(runnables[index]);
      }
    });

    updateUI();
  }

  void _bindDevicesToSelect(FlutterDeviceManager deviceManager,
      CoreElement deviceList, CoreElement runModeList) {
    SelectElement deviceElement = deviceList.element as SelectElement;

    var updateSelect = () {
      deviceList.clear();

      int index = 0;

      List<Device> devices = deviceManager.devices;
      deviceList.enabled = devices.isNotEmpty;

      if (devices.isEmpty) {
        deviceList.add(new CoreElement('option')..text = 'No devices connected');
      } else {
        for (Device device in devices) {
          deviceList.add(new CoreElement('option')..text = device.getLabel());
          if (deviceManager.currentSelectedDevice == device) {
            deviceElement.selectedIndex = index;
          }
          index++;
        }
      }
    };

    updateSelect();

    subs.add(deviceManager.onDevicesChanged.listen((List<Device> devices) => updateSelect()));
    subs.add(deviceManager.onSelectedChanged.listen((Device device) => updateSelect()));

    deviceElement.onChange.listen((e) {
      deviceManager.setSelectedDeviceIndex(deviceElement.selectedIndex);
    });

    // runModeList
    SelectElement runModeElement = runModeList.element as SelectElement;
    for (BuildMode mode in FlutterDeviceManager.runModes) {
      runModeList.add(new CoreElement('option')..text = mode.name);
    }
    runModeElement.selectedIndex = 0;
    runModeElement.onChange.listen((e) {
      deviceManager.runMode = FlutterDeviceManager.runModes[runModeElement.selectedIndex];
    });
  }

  void _handleRunLaunch() {
    RunnableConfig runnable = _workspaceLaunchManager.selectedRunnable;

    if (runnable != null) {
      RunApplicationManager runApplicationManager = deps[RunApplicationManager];
      LaunchConfiguration config = runnable.getCreateLaunchConfig();
      runApplicationManager.run(config);
    } else {
      atom.notifications.addWarning('No current launchable resource.');
    }
  }

  void _handleConfigureLaunch() {
    RunnableConfig runnable = _workspaceLaunchManager.selectedRunnable;

    if (runnable != null) {
      LaunchConfiguration config = runnable.getCreateLaunchConfig();
      atom.workspace.openPending(config.configYamlPath);
    } else {
      atom.notifications.addWarning('No current launchable resource.');
    }
  }

  void _runTests() {
    String path = atom.workspace.getActiveTextEditor()?.getPath();

    if (path == null) {
      atom.notifications.addWarning('No active editor.');
    } else {
      testManager.runTestFile(path);
    }
  }

  void _toggleOutline() {
    final String keyPath = '${pluginId}.showOutlineView';
    atom.config.setValue(keyPath, !atom.config.getBoolValue(keyPath));
  }

  void dispose() {
    leftTile.destroy();
    flutterTile.destroy();
    rightTile.destroy();
    subs.dispose();
  }
}
