
import 'dart:async';
import 'dart:html' show HttpRequest;

import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/package.dart';
import 'package:atom/node/shell.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../state.dart';

final Logger _logger = new Logger('changelog');

Future checkChangelog() => atomPackage.getPackageVersion().then(_checkChangelog);

class ChangelogManager implements Disposable {
  Disposables disposables = new Disposables();

  File _changeLogFile;

  ChangelogManager() {
    disposables.add(atom.commands.add('atom-workspace', '${pluginId}:release-notes', (_) {
      _handleReleaseNotes();
    }));
    disposables.add(atom.commands.add('atom-workspace', '${pluginId}:getting-started', (_) {
      _handleGettingStarted();
    }));
  }

  void _handleReleaseNotes() {
    Future<File> f;

    if (_changeLogFile != null) {
      f = new Future.value(_changeLogFile);
    } else {
      f = HttpRequest
          .getString('atom://dartlang/CHANGELOG.md')
          .then((contents) {
        Directory dir = new Directory.fromPath(fs.tmpdir);
        _changeLogFile = dir.getFile('CHANGELOG.md');
        _changeLogFile.writeSync(contents);
        return _changeLogFile;
      });
    }

    f.then((File file) {
      atom.workspace.open(file.path, options: {'split': 'right'});
    });
  }

  void _handleGettingStarted() {
    shell.openExternal('https://dart-atom.github.io/dartlang/');
  }

  void dispose() => disposables.dispose();
}

void _checkChangelog(String currentVersion) {
  String lastVersion = atom.config.getValue('_dartlang._version');

  if (lastVersion != currentVersion) {
    _logger.info("upgraded from ${lastVersion} to ${currentVersion}");
    atom.config.setValue('_dartlang._version', currentVersion);

    if (lastVersion != null) {
      atom.notifications.addSuccess(
          'Upgraded to dartlang plugin version ${currentVersion}.');
    }

    // HttpRequest.getString('atom://dartlang/CHANGELOG.md').then((str) {
    //   String changes;
    //   if (lastVersion != null) {
    //     changes = _extractVersion(str, lastVersion, inclusive: false);
    //   } else {
    //     changes = _extractVersion(str, currentVersion, inclusive: true);
    //   }
    //   if (changes != null && changes.isNotEmpty) {
    //     atom.notifications.addSuccess(
    //         'Upgraded to dartlang plugin version ${currentVersion}.',
    //         description: changes,
    //         dismissable: true);
    //   }
    // });
  } else {
    _logger.info("dartlang version ${currentVersion}");
  }
}

// String _extractVersion(String changelog, String last, {bool inclusive: true}) {
//   Version lastVersion = new Version.parse(last);
//   List<String> changes = changelog.split('\n');
//   Iterable itor = changes.skipWhile((line) => !line.startsWith('##'));
//   changes = itor.takeWhile((line) {
//     if (line.startsWith('## ')) {
//       try {
//         line = line.substring(3);
//         Version ver = new Version.parse(line);
//         if (inclusive) return ver >= lastVersion;
//         return ver > lastVersion;
//       } catch (_) {
//         return true;
//       }
//     }
//     return true;
//   }).toList();
//   return changes.join('\n').trim();
// }
