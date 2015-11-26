library foo_test;

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

void main(List<String> args) {
  print('args: ${args}');
  print(Directory.current);

  String abc = 'abd_def';
  int count = 78;

  Cat pebbles;
  Dog fido = new Dog(Dog.FIDO_NAME);

  dev.registerExtension('foo', _fooHandler);

  // dev.log('log from test');

  // TODO: Handle this.
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

  void bark() => print('woof!');
}

// dynamic _mockFrame() {
//   final List<String> names = [
//     'Fido', 'Sparky', 'Chips', 'Scooter'
//   ];
//
//   return names.map((name) => new Dog(name)).toList();
// }

Future<dev.ServiceExtensionResponse> _fooHandler(String method, Map parameters) {
  print('handling ${method}');
  print('params: ${parameters}');
  return new Future.value(new dev.ServiceExtensionResponse.result('bar'));
}
