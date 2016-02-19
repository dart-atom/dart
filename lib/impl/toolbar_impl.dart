
import 'dart:html' show SelectElement;

import '../atom.dart';
import '../elements.dart';
import '../flutter/flutter_devices.dart';
import '../launch/launch.dart';
import '../launch/run.dart';
import '../projects.dart';
import '../state.dart';
import '../utils.dart';
import 'toolbar.dart';

class DartToolbarContribution implements Disposable {
  ToolbarTile leftTile;
  ToolbarTile rightTile;
  StreamSubscriptions subs = new StreamSubscriptions();

  DartToolbarContribution(Toolbar toolbar) {
    leftTile = toolbar.addLeftTile(item: _buildLeftTile().element);
    rightTile = toolbar.addRightTile(item: _buildRightTile().element);
  }

  ProjectLaunchManager get projectLaunchManager => deps[ProjectLaunchManager];

  CoreElement _buildLeftTile() {
    CoreElement runButton;
    CoreElement appSelectList;
    CoreElement configureLaunchButton;

    // `settings-view` class added to get proper styling for select elements.
    CoreElement e = div(c: 'btn-group btn-group dartlang-toolbar settings-view')..add([
      runButton = button(c: 'btn icon icon-playback-play')
        ..click(_handleRunLaunch)
        ..tooltip = "Run",
      appSelectList = new CoreElement('select', classes: 'form-control'),
      configureLaunchButton = button(c: 'btn icon icon-gear')
        ..click(_handleConfigureLaunch)
        ..tooltip = 'Configure launch'
    ]);

    _bindLaunchManager(runButton, appSelectList, configureLaunchButton);

    return e;
  }

  CoreElement _buildRightTile() {
    CoreElement selectList;
    CoreElement flutterDiv;
    CoreElement outlineToggleDiv;

    // `settings-view` class added to get proper styling for select elements.
    CoreElement e = div(c: 'settings-view', a: 'flex-center')..add([
      flutterDiv = div(c: 'btn-group btn-group dartlang-toolbar')..add([
        div(c: 'icon icon-device-mobile')..id = 'toolbar-mobile-icon'
          ..tooltip = "Available devices",
        selectList = new CoreElement('select', classes: 'form-control')
      ]),
      div(c: 'btn-group btn-group dartlang-toolbar')..add([
        outlineToggleDiv = button(c: 'btn icon icon-list-unordered')
          ..click(_toggleOutline)
          ..tooltip = "Toggle Dart Outline View"
      ])
    ]);

    // Bind the device pulldown.
    FlutterDeviceManager deviceManager = deps[FlutterDeviceManager];
    _bindDevicesToSelect(deviceManager, selectList);

    void updateToolbar([_]) {
      String path = atom.workspace.getActiveTextEditor()?.getPath();
      DartProject project = projectManager.getProjectFor(path);

      bool isFlutterProject = project != null && project.isFlutterProject();
      flutterDiv.hidden(!isFlutterProject);

      outlineToggleDiv.enabled = isDartFile(path);
    }

    updateToolbar();
    editorManager.dartProjectEditors.onActiveEditorChanged.listen(updateToolbar);

    return e;
  }

  void _bindLaunchManager(
    CoreElement runButton,
    CoreElement selectList,
    CoreElement configureButton
  ) {
    SelectElement element = selectList.element as SelectElement;

    List<RunnableConfig> runnables = [];

    var updateUI = ([_]) {
      runnables = projectLaunchManager.runnables;

      runButton.enabled = runnables.isNotEmpty;
      selectList.disabled = runnables.isEmpty;
      configureButton.disabled = runnables.isEmpty;

      selectList.clear();

      if (runnables.isEmpty) {
        selectList.add(new CoreElement('option')..text = 'No runnable apps');

      } else {
        runnables.sort();

        for (RunnableConfig runnable in runnables) {
          selectList.add(new CoreElement('option')..text = runnable.getDisplayName());
        }

        int index = runnables.indexOf(projectLaunchManager.selectedRunnable);
        if (index != -1) {
          element.selectedIndex = index;
        }
      }
    };

    subs.add(projectLaunchManager.onRunnablesChanged.listen(updateUI));
    subs.add(projectLaunchManager.onSelectedRunnableChanged.listen(updateUI));

    element.onChange.listen((e) {
      int index = element.selectedIndex;
      if (index >= 0 && index < runnables.length) {
        projectLaunchManager.setSelectedRunnable(runnables[index]);
      }
    });

    updateUI();
  }

  void _bindDevicesToSelect(FlutterDeviceManager deviceManager, CoreElement selectList) {
    SelectElement element = selectList.element as SelectElement;

    var updateSelect = ([_]) {
      selectList.clear();

      int index = 0;

      List<Device> devices = deviceManager.devices;
      element.disabled = devices.isEmpty;

      if (devices.isEmpty) {
        selectList.add(new CoreElement('option')..text = 'No devices connected');
      } else {
        for (Device device in devices) {
          selectList.add(new CoreElement('option')..text = device.getLabel());
          if (deviceManager.currentSelectedDevice == device) {
            element.selectedIndex = index;
          }
          index++;
        }
      }
    };

    updateSelect();

    subs.add(deviceManager.onDevicesChanged.listen(updateSelect));
    subs.add(deviceManager.onSelectedChanged.listen(updateSelect));

    element.onChange.listen((e) {
      deviceManager.setSelectedDeviceIndex(element.selectedIndex);
    });
  }

  void _handleRunLaunch() {
    RunnableConfig runnable = projectLaunchManager.selectedRunnable;

    if (runnable != null) {
      RunApplicationManager runApplicationManager = deps[RunApplicationManager];

      LaunchConfiguration config = runnable.getCreateLaunchConfig();
      runApplicationManager.run(config);
    } else {
      atom.notifications.addWarning('No current launchable resource.');
    }
  }

  void _handleConfigureLaunch() {
    RunnableConfig runnable = projectLaunchManager.selectedRunnable;

    if (runnable != null) {
      LaunchConfiguration config = runnable.getCreateLaunchConfig();
      atom.workspace.open(config.configYamlPath);
    } else {
      atom.notifications.addWarning('No current launchable resource.');
    }
  }

  void _toggleOutline() {
    final String keyPath = '${pluginId}.showOutlineView';
    atom.config.setValue(keyPath, !atom.config.getBoolValue(keyPath));
  }

  void dispose() {
    leftTile.destroy();
    rightTile.destroy();
    subs.dispose();
  }
}
