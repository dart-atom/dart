library atom.atom_package_deps;

import 'dart:async';

import 'package:atom/atom.dart';
import 'package:atom/node/notification.dart';
import 'package:atom/node/package.dart';
import 'package:atom/node/process.dart';
import 'package:logging/logging.dart';

import 'jobs.dart';

final Logger _logger = new Logger('atom.atom_package_deps');

Future install() {
  return atomPackage.loadPackageJson().then((Map info) {
    List<String> installedPackages = atom.packages.getAvailablePackageNames();
    List<String> requiredPackages = new List.from(info['required-packages']);

    if (requiredPackages == null || requiredPackages.isEmpty) {
      return null;
    }

    Set<String> toInstall = new Set.from(requiredPackages);
    toInstall.removeAll(installedPackages);

    if (toInstall.isEmpty) return null;

    _logger.info('installing ${toInstall}');

    return new _InstallJob(toInstall.toList()).schedule();
  });
}

class _InstallJob extends Job {
  final List<String> packages;
  bool quitRequested = false;
  int errorCount = 0;

  _InstallJob(this.packages) : super("Installing Packages");

  bool get quiet => true;

  Future run() {
    packages.sort();

    Notification notification = atom.notifications.addInfo(name,
        detail: '', description: 'Installing…', dismissable: true);

    NotificationHelper helper = new NotificationHelper(notification.view);
    helper.setNoWrap();
    helper.setRunning();

    helper.appendText('Installing packages ${packages.join(', ')}.');

    notification.onDidDismiss.listen((_) => quitRequested = true);

    return Future.forEach(packages, (String name) {
      return _install(helper, name);
    }).whenComplete(() {
      if (errorCount == 0) {
        helper.showSuccess();
        helper.setSummary('Finished.');
      } else {
        helper.showError();
        helper.setSummary('Errors installing packages.');
      }
    });
  }

  Future _install(NotificationHelper helper, String name) {
    final String apm = atom.packages.getApmPath();

    ProcessRunner runner = new ProcessRunner(
        apm, args: ['--no-color', 'install', name]);
    return runner.execSimple().then((ProcessResult result) {
      if (result.stdout != null && result.stdout.isNotEmpty) {
        helper.appendText(result.stdout.trim());
      }
      if (result.stderr != null && result.stderr.isNotEmpty) {
        helper.appendText(result.stderr.trim(), stderr: true);
      }
      if (result.exit != 0) {
        errorCount++;
      } else {
        atom.packages.activatePackage(name);
      }
    });
  }
}
