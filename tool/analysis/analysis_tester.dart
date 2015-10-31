
library analysis_tester;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atom_dartlang/analysis/analysis_server_lib.dart';
import 'package:logging/logging.dart';

Server client;

void main(List<String> args) {
  if (args.length != 1) {
    print('usage: dart tool/analysis/analysis_tester.dart <sdk location>');
    exit(1);
  }

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(print);

  String sdk = args.first;
  String snapshot = '${sdk}/bin/snapshots/analysis_server.dart.snapshot';

  print('Using analysis server at ${snapshot}.');

  Process.start('dart', [snapshot, '--sdk', sdk]).then((process) {
    process.exitCode.then((code) => print('analysis server exited: ${code}'));

    Stream<String> inStream =
        process.stdout.transform(UTF8.decoder).transform(const LineSplitter());

    client = new Server(inStream, (String message) {
      print('[--> ${message}]');
      process.stdin.writeln(message);
    });

    client.server.onConnected.listen((event) {
      print('server connected: ${event}');
    });

    client.server.onError.listen((ServerError e) {
      print('server error: ${e.message}');
      print(e.stackTrace);
    });

    client.server.getVersion().then((VersionResult result) {
      print('version: ${result}, ${result.version}');
    });

    client.analysis.setAnalysisRoots([Directory.current.path], []);
  });
}
