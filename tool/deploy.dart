import 'dart:io';

import 'package:grinder/grinder.dart';
import 'package:pub_semver/pub_semver.dart';

main(List args) => grind(args);

@DefaultTask('Deploy software')
deploy() {
  deployIt();
}

deployIt() {
  // TODO: command line parsing (major, minor, patch) version update
  // Comment out the if statements while developing this task.
  var diffResult = Process.runSync("git", ["diff", "--shortstat"]);
  if (diffResult.stdout.toString().isNotEmpty)
    throw 'Index is dirty; commit files and try again';

  var syncResult = Process.runSync("git", ["rev-list", "origin..HEAD"]);
  if (syncResult.stdout.toString().isNotEmpty)
    throw 'Not synchronized with master; git push and try again';

  var packageFileData = new File('package.json').readAsStringSync();
  var yamlFileData    = new File('pubspec.yaml').readAsStringSync();
  var changelogData   = new File('CHANGELOG.md').readAsStringSync();

  var packageData = JSON.decode(packageFileData);

  var currentVersion = new Version.parse(packageData['version']);
  // TODO: have this match the parameter passed in on the command line
  var nextVersion = currentVersion.nextPatch;

  var jsonPattern         = (version) => '"version": "${version}"';
  var yamlPattern         = (version) => 'version: ${version}';
  var changelogPattern    = (version) => "# ${version}"
  // We do pattern matches to preserve the formatting in the existing files.

  var newPackageFileData =
    packageFileData.replaceFirst(jsonPattern(currentVersion),
      jsonPattern(nextVersion));
  var newYamlFileData =
    yamlFileData.replaceFirst(yamlPattern(currentVersion),
      yamlPattern(nextVersion));
  var newChangelogData =
    changelogData.replaceFirst(changelogPattern('Upcoming Version'),
      changelogPattern(nextVersion));

  new File('package.json').writeAsStringSync(newPackageFileData);
  new File('pubspec.yaml').writeAsStringSync(newYamlFileData);
  new File('CHANGELOG.md').writeAsStringSync(newChangelogData);

  Process.runSync("git", ["commit", "-a", '-m "prepare $nextVersion"']);
  Process.runSync("git", ["tag", nextVersion.toString()]);
  Process.runSync("git", ["push", "-t"]);
  Process.runSync("apm", ["publish", "-t", nextVersion.toString()]);

  print("Version ${nextVersion} has been prepared!");
  print('¯\\_(ツ)_/¯');
}
