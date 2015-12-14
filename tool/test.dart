library foo_test;

import 'dart:async';
import 'dart:convert' show JSON;
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

void main(List<String> args) {
  print('args: ${args}');
  print(Directory.current);

  String abc = 'abd_def';
  String longText = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, '
    'sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut '
    'enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut '
    'aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit '
    'in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur '
    'sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt '
    'mollit anim id est laborum.';
  int count = longText.length;

  Cat pebbles;
  Dog fido = new Dog(Dog.FIDO_NAME, parent: new Dog('Sam'));

  Map pets = {
    'pebbles': pebbles,
    fido.name: fido,
    'type': fido.runtimeType
  };

  Timer.run(() => print('timer 1'));
  Timer.run(_handleTimer);

  // dev.registerExtension('foo', fooHandler);
  //
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

  var typedList = new Int32List.fromList([1, 2, 3, 23476234]);

  dev.debugger();

  print('calcRecursive: ${calcRecursive(300)}');

  // startIsolates(4);

  // dev.log('log from test', name: 'test', level: 1);
  // dev.Timeline.timeSync('frame', _mockFrame);
  // dev.Timeline.timeSync('frame', _mockFrame);

  print('${abc} ${count}, ${pets.length}, ${typedList.length}');

  pebbles = new Cat('Pebbles');

  List animals = [
    pebbles, fido, pebbles, fido, pebbles, fido, pebbles, fido, pebbles, fido
  ];

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
  final Animal parent;

  Animal(this.name, {this.parent});

  String toString() => '[${runtimeType} ${name}]';
}

class Cat extends Animal {
  Cat(String name) : super(name);

  bool scratches() => true;
}

class Dog extends Animal {
  static String FIDO_NAME = 'Fido';

  Dog(String name, {Dog parent}) : super(name, parent: parent);

  void bark() {
    print('woof!');
  }
}

String say(String from, String to) => "move $from -> $to";

// Makes a move and recursively triggers next moves, if any.
void hanoi(int discs, String a, String b, String c) {
  // Makes a move only if there are discs.
  if (discs > 0) {
    // if (discs == 1 && a == '1') dev.debugger();

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

Future<dev.ServiceExtensionResponse> fooHandler(String method, Map parameters) {
  String result = JSON.encode({
    'type': '_extensionType',
    'method': method,
    'parameters': parameters,
  });
  return new Future.value(new dev.ServiceExtensionResponse.result(result));
}

void startIsolates(int count) {
  if (count == 0) return;

  startIsolate(count * 4);

  startIsolates(count - 1);
  startIsolates(count - 1);
}

Future<Isolate> startIsolate(int seconds) {
  return Isolate.spawn(isolateEntryPoint, seconds);
}

void isolateEntryPoint(int seconds) {
  print('[${Isolate.current}] starting');
  print('[${Isolate.current}] running for ${seconds} seconds...');
  new Timer(new Duration(seconds: seconds), () {
    print('[${Isolate.current}] exiting');
  });
}

int calcRecursive(int depth) {
  if (depth == 0) {
    return 1;
  } else {
    return depth + calcRecursive(depth - 1);
  }
}
