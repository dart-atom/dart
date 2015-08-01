
library atom.changelog;

import 'dart:html' show HttpRequest;

import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../state.dart';

final Logger _logger = new Logger('changelog');

void checkChangelog() {
  loadPackageJson().then(_checkChangelog);
}

void _checkChangelog(Map m) {
  String version = m['version'];
  String last = state['version'];

  if (last != version) {
    _logger.info("upgraded from ${last} to ${version}");

    HttpRequest.getString('atom://dartlang/CHANGELOG.md').then((str) {
      String changes;
      if (last != null) {
        changes = _extractAfterVersion(str, last);
      } else {
        changes = _extractVersion(str, version);
      }
      if (changes != null && changes.isNotEmpty) {
        atom.notifications.addSuccess(
          'Upgraded to dartlang version ${version}.',
          detail: changes,
          dismissable: true);
      }
    });
  }

  state['version'] = version;
}

String _extractVersion(String changelog, String version) {
  List<String> changes = changelog.split('\n');
  String match = '## ${version}';
  Iterable itor = changes.skipWhile((line) => line != match);
  changes = itor.takeWhile((line) => line.trim().isNotEmpty).toList();
  return changes.join('\n').trim();
}

String _extractAfterVersion(String changelog, String last) {
  Version ver = new Version.parse(last);
  List<String> changes = changelog.split('\n');
  Iterable itor = changes.skipWhile((line) => !line.startsWith('##'));
  changes = itor.takeWhile((line) {
    if (line.startsWith('## ')) {
      line = line.substring(3);
      Version v = new Version.parse(line);
      return v > ver;
    }
    return true;
  }).toList();
  return changes.join('\n').trim();
}
