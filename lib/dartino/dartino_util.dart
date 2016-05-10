import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/command.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/notification.dart';
import 'package:atom_dartlang/projects.dart';
import 'package:atom_dartlang/sdk.dart' show SdkManager;
import 'package:haikunator/haikunator.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../impl/pub.dart' show dotPackagesFileName;
import '../state.dart';
import 'dartino_project_settings.dart';
import 'sdk/dartino_sdk.dart';
import 'sdk/sdk.dart';
import 'sdk/sod_repo.dart';

const _pluginId = 'dartino';

final _Dartino dartino = new _Dartino();

final Logger _logger = new Logger(_pluginId);

Set<Directory> _checkedDirectories = new Set<Directory>();

class _Dartino {
  /// A flag indicating whether Dartino specific UI should be user visible.
  bool enabled = false;

  /// Return the device path specified in the settings or an empty string if none.
  String get devicePath {
    var path = atom.config.getValue('$_pluginId.devicePath');
    return (path is String) ? path.trim() : '';
  }

  /// Return the SDK path specified in the settings or an empty string if none.
  String get sdkPath {
    String path = atom.config.getValue('$_pluginId.sdkPath');
    return (path is String) ? path.trim() : '';
  }

  /// Return the SDK associated with the given project
  /// where [projDir] can be either a [Directory] or a directory path.
  /// If there is a problem, then notify the user and return `null`.
  /// Set `quiet: true` to supress any user notifications.
  Sdk sdkFor(projDir, {bool quiet: false}) {
    //TODO(danrubel) cache SDK path in project metadata
    String path = sdkPath;
    if (path.isEmpty) {
      if (!quiet) promptSetSdk('No SDK specified');
      return null;
    }
    Sdk sdk = DartinoSdk.forPath(path);
    if (sdk == null) sdk = SodRepo.forPath(path);
    if (sdk == null) {
      if (!quiet) promptSetSdk('Invalid SDK path specified');
      return null;
    }
    return sdk.validate(quiet: quiet) ? sdk : null;
  }

  bool isProject(projDir) => fs.existsSync(fs.join(projDir, 'dartino.yaml'));

  void createDartinoYaml(Directory directory) {
    directory.getFile('dartino.yaml').writeSync(
        r'''# This is an empty configuration file. Currently this is only used as a
# placeholder to enable the Dartino Atom package.''');
  }

  /// Prompt the user for a new project location (path)
  Future createNewProject([AtomEvent _]) async {
    var sdk = sdkFor(null);
    if (sdk == null) return;

    // Prompt for new project location
    String projectName = Haikunator.haikunate(delimiter: '_');
    String projectPath = fs.join(fs.homedir, 'dartino-projects', projectName);
    projectPath = await promptUser('Enter the path to the project to create:',
        defaultText: projectPath, selectLastWord: true);
    if (projectPath == null) return;

    // Create the project, and if successful then open it in Atom
    if (await sdk.createNewProject(projectPath)) {
      atom.project.addPath(projectPath);
      var editor = await atom.workspace.open(fs.join(projectPath, 'main.dart'));
      // Focus the file in the files view 'tree-view:reveal-active-file'.
      var view = atom.views.getView(editor);
      atom.commands.dispatch(view, 'tree-view:reveal-active-file');
    }
  }

  /// Called by the Dartino plugin to enable Dartino specific behavior.
  void enable([AtomEvent _]) {
    enabled = true;
    _logger.info('Dartino features enabled');
    projectManager.onNonProject.listen(_checkDirectory);
    projectManager.onProjectAdd
        .listen((DartProject project) => _checkDirectory(project.directory));
  }

  /// Return `true` if the Dartino plugin is installed.
  bool hasDartinoPlugin() {
    return atom.packages.getAvailablePackageNames().contains(_pluginId);
  }

  /// Open the Dartino settings page
  void openSettings([_]) {
    atom.workspace.openConfigPage(packageID: 'dartino');
  }

  /// Prompt the user to change the SDK setting or install a new SDK
  promptSetSdk(String message, {String detail}) {
    atom.notifications.addError(message,
        detail: '${detail != null ? "$detail\n \n" : ""}'
            'Click install to install a new SDK or open the settings\n'
            'to specify the path to an already existing installation.',
        buttons: [
          new NotificationButton('Install', promptInstallSdk),
          new NotificationButton('Open settings', openSettings)
        ]);
  }

  /// Prompt the user which SDK and where to install, then do it.
  void promptInstallSdk([AtomEvent _]) {
    // atom.notifications
    //     .addInfo('Which SDK would you like to install?', buttons: [
    //   new NotificationButton('Dartino', DartinoSdk.promptInstall),
    //   new NotificationButton('SOD', SodRepo.promptInstall)
    // ]);
    DartinoSdk.promptInstall();
  }

  void setMinSdkVersion() {
    if (hasDartinoPlugin()) {
      SdkManager.minVersion = new Version.parse('1.16.0');
    }
  }

  /// Show docs for the installed SDK.
  void showSdkDocs(AtomEvent _) {
    sdkFor(null)?.showDocs();
  }

  /// Validate the installed SDK if there is one.
  void validateSdk([AtomEvent _]) {
    if (sdkPath.isNotEmpty) {
      var sdk = sdkFor(null);
      if (sdk != null && sdk.validate()) {
        // If there's no Dart SDK configured, use the one provided by Dartino.
        if (sdkManager.noSdkPathConfigured) {
          sdkManager.setSdkPath(sdk.dartSdkPath);
        }

        atom.notifications
            .addSuccess('Valid ${sdk.name} detected', detail: sdkPath);
      }
    }
  }
}

/// If the directory looks like a Dartino project but missing
/// a dartino.yaml file, then notify the user and offer to create one.
void _checkDirectory(Directory dir) {
  _logger.fine('Checking directory ${dir.path}');

  // Check for dartino.yaml
  if (dartino.isProject(dir.path)) return;

  // Do not annoy user by asking more than once.
  if (!_checkedDirectories.add(dir)) return;
  var settings = new DartinoProjectSettings(dir);
  if (!settings.checkDartinoProject) return;

  // Check .packages file
  var pkgsFile = new File.fromPath(fs.join(dir.path, dotPackagesFileName));
  if (pkgsFile.existsSync()) {
    if (containsDartinoReferences(pkgsFile.readSync(), dartino.sdkPath)) {
      _promptCreateDartinoYaml(dir, settings);
    }
    return;
  }

  // dartlang already warns the user if the parent dir is a DartProject
  if (ProjectManager.isDartProject(dir.getParent())) return;

  // Check if project contains *.dart files.
  if (_hasDartFile(dir, 2)) {
    _promptCreateDartinoYaml(dir, settings);
  }
}

/// Scan [dir] to the specified [depth] looking for Dart files.
bool _hasDartFile(Directory dir, int depth) {
  for (Entry entry in dir.getEntriesSync()) {
    if (entry.isDirectory()) {
      if (depth > 1 && !entry.getPath().startsWith('.')) {
        if (_hasDartFile(dir, depth - 1)) return true;
      }
    } else if (entry.isFile()) {
      if (entry.getPath().endsWith('.dart')) return true;
    }
  }
  return false;
}

/// Notify the user that this appears to be a Dartino project without
/// a dartino.yaml file... and offer to create one.
void _promptCreateDartinoYaml(Directory dir, DartinoProjectSettings settings) {
  Notification info;
  info = atom.notifications.addWarning('Is this a Dartino project?',
      detail: 'This appears to be a Dartino project,\n'
          'but does not contain a "dartino.yaml" file.\n'
          ' \n'
          '${dir.path}\n'
          ' \n'
          'Create a "dartino.yaml" file?\n',
      buttons: [
        new NotificationButton('Yes', () {
          info.dismiss();
          try {
            dartino.createDartinoYaml(dir);
          } catch (e, s) {
            atom.notifications.addError(
                'Failed to create new "dartino.yaml" file',
                detail: '${dir.path}\n$e\n$s',
                dismissable: true);
          }
        }),
        new NotificationButton('No', () {
          info.dismiss();
          settings.checkDartinoProject = false;
        })
      ],
      dismissable: true);
}

/// Return `true` if the specified packages file content
/// contains references to Dartino or SOD packages.
bool containsDartinoReferences(String content, String sdkPath) {
  if (content == null || sdkPath == null) return false;
  if (content.isEmpty || sdkPath.isEmpty) return false;
  String path = new Uri.file(sdkPath).toString();
  if (!path.startsWith('file://')) return false;
  for (String line in content.split('\n')) {
    if (line.contains(path)) return true;
  }
  return false;
}
