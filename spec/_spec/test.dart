library test;

@MirrorsUsed(metaTargets: const [Test])
import 'dart:mirrors';

import 'jasmine.dart' as jasmine;

class Test {
  const Test();
}

/// TODO: doc
registerSuite(Type testSuite) => _registerSuite(testSuite);

/// TODO: doc
registerSuites(List<Type> testSuites) => testSuites.forEach(registerSuite);

/// TODO: doc
abstract class TestSuite {
  // /// Called once before any test in the test suite is run.
  // setUpSuite() {
  //
  // }

  /// Called before each test in the test suite has run. Can return a Future to
  /// indicate that the setup is async.
  setUp() {

  }

  /// Called after each test in the test suite has run. Can return a Future to
  /// indicate that the tearDown is async.
  tearDown() {

  }

  // /// Called once after all the tests in a test suite has run.
  // tearDownSuite() {
  //
  // }

  /// Used to validate test expectations.
  expect(Object actual, Object expected) {
    jasmine.expect(actual).toBe(expected);
  }
}

// Impl.

_registerSuite(Type testSuite) {
  ClassMirror classMirror = reflectClass(testSuite);

  String suiteName = _symbolName(classMirror.simpleName);
  print(suiteName);

  jasmine.describe(suiteName, () {
    TestSuite suite = classMirror.newInstance(const Symbol(''), []).reflectee;

    // // Call setUpSuite.
    // jasmine.beforeAll(() {
    //   return reflect(suite).invoke(#setUpSuite, []);
    // });

    // Call setUp.
    jasmine.beforeEach(() {
      return reflect(suite).invoke(#setUp, []);
    });

    // Call tearDown.
    jasmine.afterEach(() {
      return reflect(suite).invoke(#tearDown, []);
    });

    // // Call tearDownSuite.
    // jasmine.afterAll(() {
    //   return reflect(suite).invoke(#tearDownSuite, []);
    // });

    classMirror.instanceMembers.forEach((Symbol name, MethodMirror method) {
      if (method.metadata.any((meta) => meta.reflectee is Test)) {
        String testName = _symbolName(name);
        print("  - ${testName}");

        jasmine.it(testName, () {
          reflect(suite).invoke(name, []);
        });
      }
    });
  });
}

// Symbol("CatTest") ==> CatTest
String _symbolName(Symbol symbol) {
  String name = symbol.toString();
  if (name.startsWith('Symbol("')) name = name.substring(8);
  if (name.endsWith('")')) name = name.substring(0, name.length - 2);
  return name;
}
