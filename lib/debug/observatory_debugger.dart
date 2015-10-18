library atom.observatory_debugger;

import 'package:logging/logging.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import '../atom.dart';

//final Logger _logger = new Logger('atom.observatory_debugger');

String printFunctionName(FuncRef ref, {bool terse: false}) {
  String name = terse ? ref.name : '${ref.name}()';

  if (ref.owner is ClassRef) {
    return '${ref.owner.name}.${name}';
  } else if (ref.owner is FuncRef) {
    return '${printFunctionName(ref.owner, terse: true)}.${name}';
  } else {
    return name;
  }
}

Point calcPos(Script script, int tokenPos) {
  List<List<int>> table = script.tokenPosTable;

  for (List<int> row in table) {
    int line = row[0];

    int index = 1;

    while (index < row.length - 1) {
      if (row[index] == tokenPos) return new Point.coords(line, row[index + 1]);
      index += 2;
    }
  }

  return null;
}

class ObserveLog extends Log {
  final Logger logger;

  ObserveLog(this.logger);

  void warning(String message) => logger.warning(message);
  void severe(String message) => logger.severe(message);
}
