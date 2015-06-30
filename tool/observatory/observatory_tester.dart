
library observatory_tester;

import 'dart:io';

import 'dart:async';
import 'dart:convert';

import 'package:atom_dart_lang_experimental/impl/observatory_gen.dart';
import 'package:logging/logging.dart';

Observatory observatory;

// TODO: connect to the observatory

// TODO: perform some actions

// TODO: listen for events

final String host = 'localhost';
final int port = 7575;

main(List<String> args) async {
  if (args.length != 1) {
    print('usage: dart tool/observatory/observatory_tester.dart <sdk location>');
    exit(1);
  }

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(print);

  String sdk = args.first;

  print('Using sdk at ${sdk}.');

  // pause_isolates_on_start, pause_isolates_on_exit
  Process process = await Process.start('${sdk}/bin/dart', [
      '--pause_isolates_on_start',
      '--enable-vm-service=${port}',
      'tool/observatory/sample_main.dart'
  ]);

  print('dart process started');

  process.exitCode.then((code) => print('observatory exited: ${code}'));
  process.stdout.transform(UTF8.decoder).listen(print);
  process.stderr.transform(UTF8.decoder).listen(print);

  await new Future.delayed(new Duration(milliseconds: 500));

  WebSocket socket = await WebSocket.connect('ws://$host:$port/ws');

  print('socket connected');

  StreamController<String> _controller = new StreamController();
  socket.listen((data) {
    _controller.add(data);
  });

  observatory = new Observatory(_controller.stream, (String message) {
    socket.add(message);
  });

  observatory.onSend.listen((str)    => print('--> ${str}'));
  observatory.onReceive.listen((str) => print('<-- ${str}'));

  observatory.onIsolateEvent.listen(print);
  observatory.onDebugEvent.listen(print);
  observatory.onGcEvent.listen(print);

  observatory.streamListen('Isolate');
  observatory.streamListen('Debug');

  VM vm = await observatory.getVM();
  print(await observatory.getVersion());
  List<IsolateRef> isolates = await vm.isolates;
  print(isolates);

  IsolateRef isolateRef = isolates.first;
  print(await observatory.resume(isolateRef.id));

  observatory.dispose();
  socket.close();
  process.kill();
}
