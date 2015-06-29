
import 'dart:io';

import 'dart:async';
import 'dart:convert';

import 'package:atom_dart_lang_experimental/impl/analysis_server_gen.dart';
import 'package:logging/logging.dart';

Server client;

void main(List<String> args) {
  if (args.length != 1) {
    print('usage: dart tool/src/as_stub.dart <sdk location>');
    exit(1);
  }

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(print);

  String sdk = args.first;
  String snapshot = '${sdk}/bin/snapshots/analysis_server.dart.snapshot';

  print('Using analysis server at ${snapshot}.');

  Process.start('dart', [snapshot, '--sdk', sdk]).then((process) {
    process.exitCode.then((code) => print('analysis server exited: ${code}'));

    Stream inStream = process.stdout.transform(UTF8.decoder).transform(const LineSplitter());

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
