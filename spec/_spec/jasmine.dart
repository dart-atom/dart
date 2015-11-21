library jasmine;

//import 'dart:async';
import 'dart:js';

// describe("A suite", function(done) {
//   it("contains spec with an expectation", function() {
//     expect(true).toBe(true);
//   });
// });

final JsFunction _describe = context['describe'];
final JsFunction _it = context['it'];
final JsFunction _expect = context['expect'];

typedef dynamic Callback();

describe(String name, describeClosure) {
  return _describe.apply([name, describeClosure]);
}

it(String description, Callback test) {
  return _it.apply([description, test]);
}

Expectation expect(dynamic value) {
  return new Expectation(_expect.apply([value]));
}

beforeAll(Callback callback) {
  context.callMethod('beforeAll', [callback]);
}

// TODO: Re-do this to support Jasmine 1.3
// (http://jasmine.github.io/1.3/introduction.html) - runs(), waitsFor(), runs()
beforeEach(Callback callback) {
  context.callMethod('beforeEach', [callback]);
  // _beforeEach.apply([(_done) {
  //   Done done = new Done(_done);
  //   dynamic result = callback();
  //   if (result is Future) {
  //     result
  //         .then((_) => done.finished())
  //         .catchError((e) => done.fail(e));
  //   } else {
  //     done.finished();
  //   }
  // }]);
}

afterEach(Callback callback) {
  context.callMethod('afterEach', [callback]);
  // _afterEach.apply([(_done) {
  //   Done done = new Done(_done);
  //   dynamic result = callback();
  //   if (result is Future) {
  //     result
  //         .then((_) => done.finished())
  //         .catchError((e) => done.fail(e));
  //   } else {
  //     done.finished();
  //   }
  // }]);
}

afterAll(Callback callback) {
  context.callMethod('afterAll', [callback]);
}

class Expectation {
  final JsObject obj;

  Expectation(this.obj);

  toBe(dynamic value) {
    return obj.callMethod('toBe', [value]);
  }
}

// Jasmine 2.0
// class Done {
//   final JsObject obj;
//
//   Done(this.obj);
//
//   finished() {
//     (obj as JsFunction).apply([]);
//   }
//
//   fail([dynamic error]) {
//     if (error != null) {
//       obj.callMethod('fail', [error]);
//     } else {
//       obj.callMethod('fail');
//     }
//   }
// }
