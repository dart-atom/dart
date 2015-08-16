
library atom.changelog;

import 'dart:html' show HttpRequest;

import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../atom.dart';
import '../atom_utils.dart';
import '../elements.dart';
import '../js.dart';
import '../state.dart';
import '../utils.dart';

final Logger _logger = new Logger('changelog');

checkChangelog() => getPackageVersion().then(_checkChangelog);

class ChangelogManager implements Disposable {
  Disposables disposables = new Disposables();

  ChangelogManager() {
    disposables.add(atom.commands.add('atom-workspace', 'dartlang:getting-started', (_) {
      _handleOpen();
    }));

    disposables.add(atom.workspace.addOpener(_urlOpener));
  }

  dynamic _urlOpener(String url, Map options) {
    if (url == 'atom://dartlang/CHANGELOG.md') {
      CoreElement element = div(text: 'foo')..add([
        para(text: 'bar'),
        para(text: 'baz')
      ]);

      Map m = {
        'getTitle': () => 'Release notes',
        'getViewClass': () => (foo) {
          // TODO: I can't get a js element to return from here.
          return element.element;
        }
      };

      return jsify(m);
    }

    return null;
  }

  void _handleOpen() {
    atom.workspace.open(
      'atom://dartlang/CHANGELOG.md', options: {'split': 'right'});
  }

  void dispose() => disposables.dispose();
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
          description: changes,
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
