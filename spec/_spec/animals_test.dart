import 'test.dart';

register() {
  registerSuites([
    new CatTest(),
    new DogTest()
  ]);
}

class CatTest extends TestSuite {
  setUp() {
    print('I was set up!');
  }

  tearDown() {
    print('I was torn down.');
  }

  Map<String, Test> getTests() => {
    'hasPaws': _hasPaws,
    'has4Paws': _has4Paws
  };

  _hasPaws() {
    expect(true, true);
  }

  _has4Paws() {
    expect(2, 4);
  }
}

class DogTest extends TestSuite {
  Map<String, Test> getTests() => {
    'fooBar': _fooBar
  };

  _fooBar() {
    expect(4, 4);
  }
}
