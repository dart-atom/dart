library atom.debounce;

import 'dart:async';

class Debounce<T> implements StreamTransformer<T, T> {
  final Duration duration;

  Timer _timer;

  Debounce(this.duration);

  Stream<T> bind(Stream<T> stream) {
    StreamController<T> controller = new StreamController();

    StreamSubscription<T> sub;

    sub = stream.listen((T data) {
      _timer?.cancel();
      _timer = new Timer(duration, () => controller.add(data));
    }, onDone: () => sub.cancel());

    return controller.stream;
  }

  void cancel() => _timer?.cancel();
}
