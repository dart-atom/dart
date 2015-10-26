
import '../atom.dart';

/// [line] and [column] are 1-based.
Range debuggerCoordsToEditorRange(int line, int column) {
  int l = line - 1;
  int c = column == null ? 0 : column - 1;

  return new Range.fromPoints(
    new Point.coords(l, c), new Point.coords(l, c + 1));
}
