import 'package:flutter_test/flutter_test.dart';

import 'package:virtual_hid/ble/ble_client.dart';

void main() {
  test('RttStats calculates aggregate values', () {
    const RttStats stats = RttStats(samples: <int>[12, 18, 30]);

    expect(stats.count, 3);
    expect(stats.averageMs, 20);
    expect(stats.maxMs, 30);
  });

  test('RttStats handles empty samples', () {
    const RttStats stats = RttStats(samples: <int>[]);

    expect(stats.count, 0);
    expect(stats.averageMs, 0);
    expect(stats.maxMs, 0);
  });
}
