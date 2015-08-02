
library atom.changelog;

import 'dart:html' show HttpRequest;

import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../state.dart';

final Logger _logger = new Logger('changelog');

void checkChangelog() {
  getPackageVersion().then(_checkChangelog);
}

void _checkChangelog(String currentVersion) {
  String lastVersion = state['version'];

  if (lastVersion != currentVersion) {
    _logger.info("upgraded from ${lastVersion} to ${currentVersion}");

    HttpRequest.getString('atom://dartlang/CHANGELOG.md').then((str) {
      String changes;
      if (lastVersion != null) {
        changes = _extractVersion(str, lastVersion, inclusive: false);
      } else {
        changes = _extractVersion(str, currentVersion, inclusive: true);
      }
      if (changes != null && changes.isNotEmpty) {
        atom.notifications.addSuccess(
          'Upgraded to dartlang plugin version ${currentVersion}.',
          detail: changes,
          dismissable: true);
      }
    });
  }

  state['version'] = currentVersion;
}

String _extractVersion(String changelog, String last, {bool inclusive: true}) {
  Version lastVersion = new Version.parse(last);
  List<String> changes = changelog.split('\n');
  Iterable itor = changes.skipWhile((line) => !line.startsWith('##'));
  changes = itor.takeWhile((line) {
    if (line.startsWith('## ')) {
      try {
        line = line.substring(3);
        Version ver = new Version.parse(line);
        if (inclusive) return ver >= lastVersion;
        return ver > lastVersion;
      } catch (_) {
        return true;
      }
    }
    return true;
  }).toList();
  return changes.join('\n').trim();
}
