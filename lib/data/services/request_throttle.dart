import 'dart:async';

/// Paces burst-prone panel calls (the per-channel EPG lookups): at most
/// [maxConcurrent] requests in flight and at least [minGap] between two
/// request starts, FIFO. Scrolling a grid of hundreds of channels used to
/// fire hundreds of API calls in a few seconds — panels with flood
/// protection read that as abuse and can block the account. Pacing keeps the
/// panel happy while tiles still fill in progressively.
class RequestThrottle {
  RequestThrottle({
    int maxConcurrent = 2,
    this.minGap = const Duration(milliseconds: 150),
  }) : _free = maxConcurrent;

  int _free;
  final Duration minGap;
  final List<Completer<void>> _queue = [];
  DateTime _lastStart = DateTime.fromMillisecondsSinceEpoch(0);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_free > 0) {
      _free--;
    } else {
      final gate = Completer<void>();
      _queue.add(gate);
      await gate.future; // released by a finishing task, slot handed over
    }
    try {
      final wait = _lastStart.add(minGap).difference(DateTime.now());
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      _lastStart = DateTime.now();
      return await task();
    } finally {
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      } else {
        _free++;
      }
    }
  }
}
