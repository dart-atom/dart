
import 'package:atom/atom.dart';
import 'package:atom/node/fs.dart';
import 'package:atom/node/workspace.dart';

/// [line] and [column] are 1-based.
Range debuggerCoordsToEditorRange(int line, int column) {
  int l = line - 1;
  int c = column == null ? 0 : column - 1;

  return new Range.fromPoints(
    new Point.coords(l, c), new Point.coords(l, c + 1)
  );
}

LineColumn editorRangeToDebuggerCoords(Range range) {
  Point p = range.start;
  return new LineColumn(p.row + 1, p.column + 1);
}

String getDisplayUri(String uri) {
  if (uri == null) return null;

  if (uri.startsWith('file:')) {
    String path = Uri.parse(uri).toFilePath();
    return atom.project.relativizePath(path)[1];
  } else if (fs.existsSync(uri)) {
    return atom.project.relativizePath(uri)[1];
  } else if (uri.startsWith('packages/')) {
    return 'package:${uri.substring(9)}';
  }

  return uri;
}

class LineColumn {
  final int line;
  final int column;

  LineColumn(this.line, this.column);
}
