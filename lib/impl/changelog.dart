
library atom.changelog;

import 'dart:html' show HttpRequest;

import 'package:logging/logging.dart';

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
      List<String> changes = str.split('\n');
      String match = '## ${version}';
      Iterable itor = changes.skipWhile((line) => line != match);
      changes = itor.takeWhile((line) => line.trim().isNotEmpty).toList();
      if (changes.isNotEmpty) {
        atom.notifications.addSuccess(
          'Upgraded to dartlang plugin version ${version}.',
          detail: changes.join('\n'),
          dismissable: true);
      }
    });
  }

  state['version'] = version;
}
