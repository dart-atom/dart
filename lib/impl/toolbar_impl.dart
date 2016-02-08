import 'dart:html' show SelectElement;

import '../atom.dart';
import '../elements.dart';
import '../flutter/flutter_devices.dart';
import '../state.dart';
import '../utils.dart';
import 'toolbar.dart';

class DartToolbarContribution implements Disposable {
  ToolbarTile leftTile;
  ToolbarTile rightTile;
  Disposable editorWatcher;
  StreamSubscriptions subs = new StreamSubscriptions();
  _ProjectLaunchManager projectLaunchManager;

  // CoreElement back;
  // CoreElement forward;

  DartToolbarContribution(Toolbar toolbar) {
    leftTile = toolbar.addLeftTile(item: _buildLeftTile().element);
    rightTile = toolbar.addRightTile(item: _buildRightTile().element);
  }

  CoreElement _buildLeftTile() {
    CoreElement runButton;
    CoreElement appSelectList;
    CoreElement configureLaunchButton;

    // `settings-view` class added to get proper styling for select elements.
    CoreElement e = div(c: 'btn-group btn-group dartlang-toolbar settings-view')..add([
      runButton = button(c: 'btn icon icon-playback-play')..tooltip = "Run",
      appSelectList = new CoreElement('select', classes: 'form-control'),
      // TODO: add a 'pinned' checkbox?
      configureLaunchButton = button(c: 'btn icon icon-gear')
        ..click(_handleConfigureLaunch)
        ..tooltip = 'Configure launch'
    ]);

    // Run button.
    runButton.click(() {
      TextEditor editor = atom.workspace.getActiveTextEditor();

      if (editor == null) {
        atom.notifications.addWarning('No active text editor.');
      } else {
        atom.commands.dispatch(atom.views.getView(editor), 'dartlang:run-application');
      }
    });

    editorWatcher = atom.workspace.observeActivePaneItem((_) {
      runButton.enabled = atom.workspace.getActiveTextEditor() != null;
    });

    _bindLaunchManager(appSelectList, configureLaunchButton);

    return e;
  }

  CoreElement _buildRightTile() {
    CoreElement selectList;

    // `settings-view` class added to get proper styling for select elements.
    CoreElement e = div(c: 'settings-view', a: 'flex-center')..add([
      div(c: 'btn-group btn-group dartlang-toolbar')..add([
        span(c: 'icon icon-device-mobile')..id = 'toolbar-mobile-icon'
          ..tooltip = "Available devices",
        selectList = new CoreElement('select', classes: 'form-control')
      ]),
      div(c: 'btn-group btn-group dartlang-toolbar')..add([
        button(c: 'btn icon icon-list-unordered')
          ..click(_toggleOutline)
          ..tooltip = "Toggle Outline View"
      ])
      // div(c: 'btn-group btn-group dartlang-toolbar')..add([
      //   back = button(c: 'btn icon icon-arrow-left')..tooltip = "Back",
      //   forward = button(c: 'btn icon icon-arrow-right')..tooltip = "Forward"
      // ])
    ]);

    // back.disabled = true;
    // back.click(() => navigationManager.goBack());
    // forward.disabled = true;
    // forward.click(() => navigationManager.goForward());
    //
    // navigationManager.onNavigate.listen((_) {
    //   back.disabled = !navigationManager.canGoBack();
    //   forward.disabled = !navigationManager.canGoForward();
    // });

    // Device pulldown.
    FlutterDeviceManager deviceManager = deps[FlutterDeviceManager];
    _bindDevicesToSelect(deviceManager, selectList);

    return e;
  }

  void _bindLaunchManager(CoreElement selectList, CoreElement configureButton) {
    SelectElement element = selectList.element as SelectElement;

    // TODO:
    // launchManager;

    element.disabled = true;
    selectList.add(new CoreElement('option')..text = 'No runnable apps');
    configureButton.disabled = true;
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
          CoreElement option = selectList.add(new CoreElement('option')..text = device.getLabel());
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

  void _handleConfigureLaunch() {
    // TODO:

    atom.notifications.addWarning('TODO: handle configure launch button');
  }

  void _toggleOutline() {
    final String keyPath = '${pluginId}.showOutlineView';
    atom.config.setValue(keyPath, !atom.config.getBoolValue(keyPath));
  }

  void dispose() {
    leftTile.destroy();
    rightTile.destroy();
    editorWatcher.dispose();
    subs.dispose();
    projectLaunchManager?.dispose();
  }
}

// TODO: have a selected launch

// TODO: have a list of all launches

// TODO: listen to active resource changes

class _ProjectLaunchManager implements Disposable {

  void dispose() {
    // TODO: implement dispose

  }
}
