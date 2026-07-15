import 'dart:math' as math;

import 'package:broken_iptv/data/services/request_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never runs more than maxConcurrent tasks at once', () async {
    final throttle = RequestThrottle(maxConcurrent: 2, minGap: Duration.zero);
    var active = 0;
    var peak = 0;

    Future<void> job() => throttle.run(() async {
          active++;
          peak = math.max(peak, active);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
        });

    await Future.wait([for (var i = 0; i < 8; i++) job()]);
    expect(peak, lessThanOrEqualTo(2));
    expect(active, 0);
  });

  test('propagates results and errors, keeps serving afterwards', () async {
    final throttle = RequestThrottle(maxConcurrent: 1, minGap: Duration.zero);
    expect(await throttle.run(() async => 42), 42);
    await expectLater(
      throttle.run<int>(() async => throw StateError('boom')),
      throwsStateError,
    );
    // The failed task must have released its slot.
    expect(await throttle.run(() async => 7), 7);
  });
}
