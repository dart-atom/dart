library atom.debugger_tooltip;

import 'dart:async';
import 'dart:math' as math;

import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';
import 'package:petitparser/petitparser.dart';

import '../analysis_server.dart';
import '../elements.dart';
import '../impl/tooltip.dart';
import '../material.dart';
import '../state.dart';
import '../utils.dart';

import './debugger_ui.dart';
import './model.dart';

final Logger _logger = new Logger('atom.debugger_tooltip');

class DebugTooltipManager implements Disposable {

  final Property<int> endOffset = new Property();

  Parser reverseContextParser;


  DebugTooltipManager() {
    var expression = undefined();
    var index = undefined();
    var ref = undefined();
    var id = undefined();

    Parser trim(String c) => char(c).trim();
    Parser tagged(Parser p) => new TagPositionParser(p, endOffset);

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
  dynamic reverseParse(dynamic value) {
    if (value is String) {
      return reverseString(value);
    } else if (value is List) {
      return value.reversed.map((v) => reverseParse(v)).toList();
    } else {
      return value;
    }
  }

  String reverseString(String input) =>
      new String.fromCharCodes(input.codeUnits.reversed);

  // This is how many characters back at most we go to get the full context.
  static const backwardBuffer = 160;

  Future check(TooltipElement tooltip) async {
    HoverInformation info = tooltip.info;
    TextEditor editor = tooltip.editor;

    int startOffset = math.max(0, info.offset - backwardBuffer);
    int endOffset = info.offset + info.length;
    String input = reverseString(editor.getTextInBufferRange(new Range.fromPoints(
        editor.getBuffer().positionForCharacterIndex(startOffset),
        editor.getBuffer().positionForCharacterIndex(endOffset))));

    this.endOffset.value = endOffset;

    for (var connection in debugManager.connections) {
      if (!connection.isAlive) continue;

      DebugVariable result;
      try {
        // Parse in reverse from cursor, then let the evaluator unparse it
        // adding custom context information if needed.
        var expression = reverseParse(reverseContextParser.parse(input).value);
        // Let actual debugger to the eval.
        result = await connection.eval(new DebugExpression(editor.getPath(), expression));
        if (result == null) return;
      } catch (e) {
        _logger.warning(e);
        break;
      }

      // If we have anything we create the MTree to display it in the tooltip.
      MTree<DebugVariable> row = new MTree(new LocalTreeModel(), ExecutionTab.renderVariable)
          ..flex()
          ..toggleClass('has-debugger-data');

      row.selectedItem.onChanged.listen((variable) async {
        if (variable == null) return;
        await variable.value.invokeToString();
        await row.updateItem(variable);
      });

      await row.update([result]);

      String clazz = 'debugger-data';
      // TODO: this might change after eval of a getter
      if (!result?.value?.isPrimitive ?? false) clazz += ' expandable';
      tooltip.expand(div(c: clazz)..add(row));
    }
  }

  void dispose() {}
}

class TooltipEvaluator {
  final DebugExpression expression;

  TooltipEvaluator(this.expression);

  Future eval() async => visitExpression(expression.expression);

  Future<String> visitExpression(expression) async {
    if (expression is String) return expression;
    if (expression is! List || expression.isEmpty) return '';
    List<String> parts = [];
    parts.add(await visitFirstReference(expression[0]));
    for (var sub in expression[1]) {
      parts.add(await visitNextReference(sub));
    }
    return parts.join();
  }

  Future<String> visitFirstReference(expression) async =>
      visitReference(true, expression);

  Future<String> visitNextReference(expression) async {
    if (expression is String) return expression;
    if (expression is! List || expression.isEmpty) return '';
    String right  = await visitReference(false, expression[1]);
    return '.$right';
  }

  Future<String> visitReference(bool first, expression) async {
    if (expression is String) return expression;
    if (expression is! List || expression.isEmpty) return '';
    String left = await visitReferenceIdentifier(first, expression[0]);
    String right = await visitIndex(expression[1]);
    return '$left$right';
  }

  Future<String> visitReferenceIdentifier(bool first, expression) async {
    if (expression is String) return expression;
    if (expression is! List || expression.isEmpty) return '';
    return mapReferenceIdentifier(first, expression[1], expression[0]);
  }

  /// For example, here we would override this in a js debugger to add 'this'
  /// to the first (leftmost) identifier if needed.
  Future<String> mapReferenceIdentifier(bool first, int offset, String identifier) async {
    return identifier;
  }

  Future<String> visitIndex(expression) async {
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
