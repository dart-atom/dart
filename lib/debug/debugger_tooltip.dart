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

import './debugger_ui.dart';
import './model.dart';

final Logger _logger = new Logger('atom.debugger_tooltip');

class DebugTooltipManager implements Disposable {

  Parser reverseContextParser;

  DebugTooltipManager() {
    var expression = undefined();
    var index = undefined();
    var ref = undefined();
    var id = undefined();

    Parser trim(String c) => char(c).trim();
    Parser tagged(Parser p) => new TagPositionParser(p);

    // This is the simple dart sub-grammar we handle for now:
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

  static const backwardBuffer = 160;

  Future check(TooltipElement tooltip) async {
    HoverInformation info = tooltip.info;
    if (info.containingLibraryPath == null || info.containingLibraryPath.isEmpty) return;

    String variable = info.elementDescription?.split(' ')?.last;
    if (variable == null) return;

    TextEditor editor = tooltip.editor;

    int startOffset = math.max(0, info.offset - backwardBuffer);
    int endOffset = info.offset + info.length;
    String input = reverseString(editor.getTextInBufferRange(new Range.fromPoints(
      editor.getBuffer().positionForCharacterIndex(startOffset),
      editor.getBuffer().positionForCharacterIndex(endOffset))));

    print('input: $input');
    print(reverseParse(reverseContextParser.parse(input).value));

    // TODO walk tree and generate expression, identifying 'this'
    // candidates (leftmost ref of each expression)
    // as you go along.
    // TODO remap offset: aa.bb -> aa@3 . bb@0 ->
    // endOffset - offset - symbol.length


    // expression :: ref ('.' ref)*
    // index :: '[' expression | number ']' e
    // ref :: identifier [ index ]
    // [[[tagged, 0], null], []]
    // [[identifier, index], []]
    // [[[tooltip, 7], null], [[., [[editor, 0], null]]]]
    // dynamic unparse(dynamic value) {
    //   if (value is String) {
    //     return reverseString(value);
    //   } else if (value is List) {
    //     return value.reversed.map((v) => reverseParse(v)).toList();
    //   } else {
    //     return value;
    //   }
    // }

    for (var connection in debugManager.connections) {
      if (!connection.isAlive) continue;

      DebugVariable result = await connection.eval(info);
      if (result == null) return;

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

  void dispose() {
  }
}

class TagPositionParser extends DelegateParser {
  TagPositionParser(Parser delegate) : super(delegate);

  @override
  Result parseOn(Context context) {
    var result = delegate.parseOn(context);
    if (result.isSuccess) {
      return result.success([context.position, result.value]);
    } else {
      return result;
    }
  }

  @override
  Parser copy() => new TagPositionParser(delegate);
}
