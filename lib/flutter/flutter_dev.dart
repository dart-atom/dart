import '../atom.dart';
import '../utils.dart';

class FlutterDev implements Disposable {
  Disposables disposables = new Disposables();

  FlutterDev() {
    disposables.add(atom.commands
        .add('atom-workspace', 'flutter:getting-started', _gettingStarted));
  }

  void dispose() => disposables.dispose();

  void _gettingStarted(_) {
    shell.openExternal('http://flutter.io/getting-started/');
  }
}
