library atom.evaluator;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:petitparser/petitparser.dart';

import '../utils.dart';
//import './model.dart';

final Logger _logger = new Logger('atom.evaluator');

class EvaluatorReverseParser {
  final Property<int> endOffset = new Property();

  Parser reverseContextParser;

  EvaluatorReverseParser() {
    SettableParser expression = undefined();
    SettableParser index = undefined();
    SettableParser ref = undefined();
    SettableParser id = undefined();

    Parser trim(String c) => char(c).trim();
    Parser tagged(Parser p) => new TagPositionParser(p, this.endOffset);

    // This is the simple dart sub-grammar we handle for now, backward:
    // expression :: ref ('.' ref)*
    // backward -> (ref '.')* ref
    expression.set((ref & trim('.')).star() & ref);
    // index :: '[' expression | number ']' e
    // backward -> ']' expression | number '['
    index.set(trim(']') & (expression | digit()) & trim('['));
    // ref :: identifier [ index ]
    // backward -> [ index ] identifier
    ref.set(index.optional() & tagged(id));

    id.set(((letter() | char('_')) & (letter() | digit() | char('_')).star())
        .flatten());

    reverseContextParser = expression;
  }

  // Put it back in flowing order.
  dynamic reverseResult(dynamic value) {
    if (value is String) {
      return reverseString(value);
    } else if (value is List) {
      return value.reversed.map((v) => reverseResult(v)).toList();
    } else {
      return value;
    }
  }

  String reverseString(String input) =>
      new String.fromCharCodes(input.codeUnits.reversed);

  dynamic parse(String input, int endOffset) {
    this.endOffset.value = endOffset;
    return reverseResult(reverseContextParser.parse(input).value);
  }
}

class EvalExpression {
  String filePath;

  /// This is the simple dart sub-grammar we handle for now:
  ///   expression :: ref ('.' ref)*
  ///   ref :: identifier [ index ]
  ///   index :: '[' expression | number ']'
  /// expression is in a List tree generate by petitparser.
  dynamic expression;

  EvalExpression(this.filePath, this.expression);
}

class Evaluator {
  final EvalExpression expression;

  Evaluator(this.expression);

  Future eval() async => visitExpression(expression.expression);

  Future<String> visitExpression(dynamic expression) async {
    if (expression is String) return expression;
    if (expression is! List || expression.isEmpty) return '';
    List<String> parts = [];
    parts.add(await visitFirstReference(expression[0]));
    for (var sub in expression[1]) {
      parts.add(await visitNextReference(sub));
    }
    return parts.join();
  }

  Future<String> visitFirstReference(dynamic expression) async =>
      visitReference(true, expression);

  Future<String> visitNextReference(dynamic expression) async {
    if (expression is String) return expression;
    if (expression is! List || expression.isEmpty) return '';
    String right = await visitReference(false, expression[1]);
    return '.$right';
  }

  Future<String> visitReference(bool first, dynamic expression) async {
    if (expression is String) return expression;
    if (expression is! List || expression.isEmpty) return '';
    String left = await visitReferenceIdentifier(first, expression[0]);
    String right = await visitIndex(expression[1]);
    return '$left$right';
  }

  Future<String> visitReferenceIdentifier(
      bool first, dynamic expression) async {
    if (expression is String) return expression;
    if (expression is! List || expression.isEmpty) return '';
    return mapReferenceIdentifier(first, expression[1], expression[0]);
  }

  /// For example, here we would override this in a js debugger to add 'this'
  /// to the first (leftmost) identifier if needed.
  Future<String> mapReferenceIdentifier(
      bool first, int offset, String identifier) async {
    return identifier;
  }

  Future<String> visitIndex(dynamic expression) async {
    if (expression is String) return expression;
    if (expression is! List || expression.isEmpty) return '';
    String inner = await visitExpression(expression[1]);
    return '[$inner]';
  }
}

class TagPositionParser extends DelegateParser {
  final Property<int> endOffset;

  TagPositionParser(Parser delegate, this.endOffset) : super(delegate);

  @override
  Result parseOn(Context context) {
    var result = delegate.parseOn(context);
    if (result.isSuccess) {
      return result.success([
        endOffset.value - context.position - result.value.length + 1,
        result.value
      ]);
    } else {
      return result;
    }
  }

  @override
  Parser copy() => new TagPositionParser(delegate, endOffset);
}
