library atom.debugger_tooltip;

import 'dart:async';
import 'dart:math' as math;

import 'package:atom/node/workspace.dart';
import 'package:atom/utils/disposable.dart';
import 'package:logging/logging.dart';

import '../analysis_server.dart';
import '../elements.dart';
import '../impl/tooltip.dart';
import '../material.dart';
import '../state.dart';

import './debugger_ui.dart';
import './evaluator.dart';
import './model.dart';

final Logger _logger = new Logger('atom.debugger_tooltip');

class DebugTooltipManager implements Disposable {
  EvaluatorReverseParser parser = new EvaluatorReverseParser();

  DebugTooltipManager();

  // This is how many characters back at most we go to get the full context.
  static const backwardBuffer = 160;

  Future check(TooltipElement tooltip) async {
    HoverInformation info = tooltip.info;
    TextEditor editor = tooltip.editor;

    int startOffset = math.max(0, info.offset - backwardBuffer);
    int endOffset = info.offset + info.length;
    String input = parser.reverseString(editor.getTextInBufferRange(
        new Range.fromPoints(
            editor.getBuffer().positionForCharacterIndex(startOffset),
            editor.getBuffer().positionForCharacterIndex(endOffset))));

    for (var connection in debugManager.connections) {
      if (!connection.isAlive) continue;

      DebugVariable result;
      try {
        // Parse in reverse from cursor, then let the evaluator unparse it
        // adding custom context information if needed.
        var expression = parser.parse(input, endOffset);
        // Let actual debugger to the eval.
        result = await connection
            .eval(new EvalExpression(editor.getPath(), expression));
        if (result == null) return;
      } catch (e) {
        _logger.warning(e);
        break;
      }

      // If we have anything we create the MTree to display it in the tooltip.
      MTree<DebugVariable> row =
          new MTree(new LocalTreeModel(), ExecutionTab.renderVariable)
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

  bool get hasOpenedConnection => debugManager.connections.any((c) => c.isAlive);

  void dispose() {}
}
