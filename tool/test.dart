library foo_test;

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

void main(List<String> args) {
  print('args: ${args}');
  print(Directory.current);

  String abc = 'abd_def';
  int count = 78;

  Cat pebbles;
  Dog fido = new Dog(Dog.FIDO_NAME);

  Timer.run(() => print('timer 1'));

  Timer.run(_handleTimer);

  dev.registerExtension('foo', _fooHandler);

  // dev.log('log from test');
  // dev.Timeline.timeSync('frame', _mockFrame);
  // dev.inspect(fido);

  // int i = 0;
  //
  // new Timer.periodic(new Duration(milliseconds: 10), (t) {
  //   print('foo ${i}');
  //   i++;
  //   if (i > 300) t.cancel();
  // });

  print('foo 1');
  print('foo 2');
  print('foo 3');

  // startIsolates(5);

  // dev.log('log from test', name: 'test', level: 1);
  // dev.Timeline.timeSync('frame', _mockFrame);
  // dev.Timeline.timeSync('frame', _mockFrame);

  print('${abc} ${count}');

  pebbles = new Cat('Pebbles');

  List animals = [pebbles, fido];

  print(pebbles);
  print(fido);

  // if (pebbles.scratches()) {
  //   throw 'no scratching';
  // }

  print(animals);

  fido.bark();

  // Demonstrates a game with 3 discs on pegs labeled '1', '2' and '3'.
  hanoi(4, '1', '2', '3');
}

abstract class Animal {
  final String name;

  Animal(this.name);

  String toString() => '[${runtimeType} ${name}]';
}

class Cat extends Animal {
  Cat(String name) : super(name);

  bool scratches() => true;
}

class Dog extends Animal {
  static String FIDO_NAME = 'Fido';

  Dog(String name) : super(name);

  void bark() {
    print('woof!');
  }
}

String say(String from, String to) => "move $from -> $to";

// Makes a move and recursively triggers next moves, if any.
void hanoi(int discs, String a, String b, String c) {
  // Makes a move only if there are discs.
  if (discs > 0) {
    if (discs == 1 && a == '1') dev.debugger();

    // Announces this move, from A to C.
    print('[${discs}] ${say(a, c)}');

    // Triggers the next step: from A to B.
    hanoi(discs - 1, a, c, b);

    // Triggers the last step: from B to C.
    hanoi(discs - 1, b, a, c);
  }
}

// dynamic _mockFrame() {
//   final List<String> names = [
//     'Fido', 'Sparky', 'Chips', 'Scooter'
//   ];
//
//   return names.map((name) => new Dog(name)).toList();
// }

void _handleTimer() {
  print('timer 2');
}

Future<dev.ServiceExtensionResponse> _fooHandler(String method, Map parameters) {
  print('handling ${method}');
  print('params: ${parameters}');
  return new Future.value(new dev.ServiceExtensionResponse.result('bar'));
}

void startIsolates(int count) {
  if (count == 0) return;

  startIsolate(count * 4);

  startIsolates(count - 1);
  startIsolates(count - 1);
}

void startIsolate(int seconds) {
  ReceivePort port = new ReceivePort();

  Isolate.spawn(isolateEntryPoint, port.sendPort);

  port.first.then((SendPort sendPort) {
    sendPort.send(seconds);
    port.listen(print);
  });
}

void isolateEntryPoint(SendPort port) {
  print('[isolate ${Isolate.current}] starting');

  ReceivePort receivePort = new ReceivePort();
  port.send(receivePort.sendPort);

  receivePort.first.then((seconds) {
    port.send('[isolate ${Isolate.current}] running for ${seconds} seconds');

    new Timer(new Duration(seconds: seconds), () {
      port.send('[isolate ${Isolate.current}] exiting');
      receivePort.close();
    });
  });
}
