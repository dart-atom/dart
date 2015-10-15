library atom.breakpoints;

import 'package:logging/logging.dart';

import '../atom.dart';
import '../utils.dart';

final Logger _logger = new Logger('atom.breakpoints');

// TODO: persist breakpoints

// TODO: create and dispose of breakpoints

// TODO: visualize breakpoints

// TODO: track changes to breakpoint files

// TODO: track realized UI of breakpoints

// TODO: notifications for breakpoints

// TODO: Just Dart files for now
// TODO: allow files outside the workspace?

class BreakpointManager implements Disposable {
  Disposables disposables = new Disposables();

  BreakpointManager() {
    disposables.add(atom.commands.add('atom-workspace', 'dartlang:debug-toggle-breakpoint', (_) {
      _toggleBreakpoint();
    }));
  }

  void _toggleBreakpoint() {
    // TODO:
    print('todo: _toggleBreakpoint');
  }

  void dispose() => disposables.dispose();
}
