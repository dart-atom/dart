library foo_test;

void main(List<String> args) {
  String abc = 'abd_def';
  int count = 78;

  Cat pebbles;
  Dog fido = new Dog(Dog.FIDO_NAME);

  print('foo 1');
  print('foo 2');
  print('foo 3');

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
