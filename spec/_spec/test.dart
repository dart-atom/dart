library test;

import 'jasmine.dart' as jasmine;

typedef Test();

/// TODO: doc
registerSuite(TestSuite testSuite) => _registerSuite(testSuite);

/// TODO: doc
registerSuites(List<TestSuite> testSuites) => testSuites.forEach(registerSuite);

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

  /// Return the `<name, test>` tests for this test suite.
  Map<String, Test> getTests();

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

_registerSuite(TestSuite suite) {
  String suiteName = suite.runtimeType.toString();

  jasmine.describe(suiteName, () {
    // // Call setUpSuite.
    // jasmine.beforeAll(() {
    //   return reflect(suite).invoke(#setUpSuite, []);
    // });

    // Call setUp.
    jasmine.beforeEach(() => suite.setUp());

    // Call tearDown.
    jasmine.afterEach(() => suite.tearDown());

    // // Call tearDownSuite.
    // jasmine.afterAll(() {
    //   return reflect(suite).invoke(#tearDownSuite, []);
    // });

    Map<String, Test> tests = suite.getTests();

    for (String testName in tests.keys) {
      Test test = tests[testName];
      print("${suiteName} - ${testName}");
      jasmine.it(testName, () => test());
    }
  });
}
