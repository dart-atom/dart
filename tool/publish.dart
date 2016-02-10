// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library atom.publish;

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

/// Publish the Atom plugin in the current working directory.
publishAtomPlugin() {
  var pluginId = _getPluginId();
  print('publishing plugin $pluginId');

  var version = _getPubspecVersion();
  print('pubspec.yaml version is $version');
  var changeLogVersion = _getChangeLogVersion();
  print('latest version in CHANGELOG.md is $changeLogVersion');
  if (version != changeLogVersion) {
    throw 'pubspec.yaml version is not the same as version in CHANGELOG.md';
  }
  if (version.preRelease.isNotEmpty || version.build.isNotEmpty) {
    throw 'Publishing pre-release or build versions is not supported';
  }

  var unpublishedVersion = _getUnpublishedVersion();
  print('unpublished version is $unpublishedVersion');
  var publishedVersion = _getPublishedVersion(pluginId);
  print('published version is ${publishedVersion}');
  if (unpublishedVersion != publishedVersion) {
    throw 'Expected unpublished and published versions to be the same';
  }
  if (version < publishedVersion) {
    throw 'Version to be published should be greater than published version';
  }

  // Include the newly built files in the commit
  _runSync('git', ['add', 'web/*']);

  // Ensure that the tree is clean
  if (!_isGitClean()) {
    throw 'Git working directory not clean';
  }

  // runSync('git', ['commit', '-a', '-m 'prepare $version'']);
  // runSync('git', ['tag', version.toString()]);
  // runSync('git', ['push', '-t']);
  // runSync('apm', ['publish', '-t', nextVersion.toString()]);

  if (version.major != publishedVersion.major) {
    if (version.major != publishedVersion.major + 1 ||
        version.minor != 0 ||
        version.patch != 0) {
      throw 'Version to be published is not incremented correctly';
    }
    _pushNewVersion('major');
  } else if (version.minor != publishedVersion.minor) {
    if (version.minor != publishedVersion.minor + 1 || version.patch != 0) {
      throw 'Version to be published is not incremented correctly';
    }
    _pushNewVersion('minor');
  } else if (version.patch != publishedVersion.patch) {
    if (version.patch != publishedVersion.patch + 1) {
      throw 'Version to be published is not incremented correctly';
    }
    _pushNewVersion('patch');
  } else {
    print('nothing to do - version already published');
  }
}

/// Return `true` if all files are staged or committed.
bool _isGitClean() {
  bool goodCommit = true;

  String result = _runSync('git', ['ls-files', '--modified']).trim();
  if (result.isNotEmpty) {
    print('>>> Files modified but unstaged for commit:\n$result');
    goodCommit = false;
  }

  result = _runSync('git', ['ls-files', '--others', '--exclude-standard']);
  if (result.isNotEmpty) {
    print('>>> Untracked files:\n$result');
    goodCommit = false;
  }

  result = _runSync('git', ['status']);
  if (result.contains('Changes to be committed')) {
    print('>>> Uncommitted files:\n$result');
    goodCommit = false;
  }

  _runSync('git', ['fetch']);
  result = _runSync('git', ['diff', 'origin/master', 'master']);
  if (result.isNotEmpty)
    throw 'Not synchronized with master; git pull and try again';

  return goodCommit;
}

/// Publish a new version where [publishType] is 'major', 'minor', or 'patch'.
void _pushNewVersion(String publishType) {
  print('publishing $publishType version ...');
  var result = _runSync('apm', ['publish', publishType]);
  print(result);
  print('publish complete');
}

/// Return the version found in the pubspec.yaml file.
Version _getPubspecVersion() {
  var pubspecFile = new File('pubspec.yaml');
  var lines = pubspecFile.readAsLinesSync();
  int lineNum = 1;
  for (String line in lines) {
    if (line.startsWith('version:')) {
      try {
        return new Version.parse(line.substring(8).trim());
      } on FormatException {
        throw 'expected to find version in $pubspecFile\n'
            'but on line $lineNum found $line';
      }
    }
    ++lineNum;
  }
  throw 'Failed to find version in $pubspecFile';
}

/// Return the first version found in the CHANGELOG.md file.
Version _getChangeLogVersion() {
  var changeLogFile = new File('CHANGELOG.md');
  var lines = changeLogFile.readAsLinesSync();
  int lineNum = 1;
  for (String line in lines) {
    if (line.startsWith('## ')) {
      try {
        return new Version.parse(line.substring(3).trim());
      } on FormatException {
        throw 'expected to find version in $changeLogFile\n'
            'but on line $lineNum found $line';
      }
    }
    ++lineNum;
  }
  throw 'Failed to find version in $changeLogFile';
}

/// Return the plugin ID as specified in the package.json file.
String _getPluginId() {
  var packageFile = new File('package.json');
  var packageContent = packageFile.readAsStringSync();
  Map json = JSON.decode(packageContent);
  return json['name'];
}

/// Return the version specified in the package.json file.
Version _getUnpublishedVersion() {
  var packageFile = new File('package.json');
  var packageContent = packageFile.readAsStringSync();
  Map json = JSON.decode(packageContent);
  return new Version.parse(json['version']);
}

/// Return the currently published version of the specified package.
Version _getPublishedVersion(String pluginId) {
  var result = _runSync('apm', ['show', pluginId, '--json']);
  if (result.isEmpty) {
    throw 'Cannot find published version for plugin "$pluginId"';
  }
  Map pkgInfo = JSON.decode(result);
  return new Version.parse(pkgInfo['version']);
}

/// Run the specified external process and return contents of stdout.
/// Throw an exception if there is an error.
String _runSync(String executable, List<String> arguments) {
  var result = Process.runSync(executable, arguments);
  if (result.exitCode != 0 || result.stderr.isNotEmpty) {
    throw 'Process exception:'
        '\n  $executable'
        '\n  $arguments'
        '\n  exit code ${result.exitCode}'
        '\n${result.stdout}'
        '\n${result.stdout}';
  }
  return result.stdout;
}
