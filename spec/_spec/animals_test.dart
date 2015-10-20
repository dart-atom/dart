@MirrorsUsed(targets: const [CatTest, DogTest])
import 'dart:mirrors';

import 'test.dart';

register() {
  registerSuites([
    CatTest,
    DogTest
  ]);
}

class CatTest extends TestSuite {
  setUp() {
    print('I was set up!');
  }

  tearDown() {
    print('I was torn down.');
  }

  @Test()
  hasPaws() {
    expect(true, true);
  }

  @Test()
  has4Paws() {
    expect(2, 4);
  }
}

class DogTest extends TestSuite {
  @Test()
  fooBar() {
    expect(4, 4);
  }
}
