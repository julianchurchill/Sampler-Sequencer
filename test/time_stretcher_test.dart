import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sampler_sequencer/audio/time_stretcher.dart';

void main() {
  // -------------------------------------------------------------------------
  group('timeStretch', () {
    test('empty input returns empty output', () {
      final result = timeStretch(Float64List(0), 2.0);
      expect(result.length, equals(0),
          reason: 'empty input → empty output regardless of ratio');
    });

    test('ratio 1.0 returns same length as input', () {
      const n = 4410; // 100 ms at 44100 Hz
      final signal = Float64List(n)..fillRange(0, n, 0.5);
      final result = timeStretch(signal, 1.0);
      expect(result.length, equals(n),
          reason: 'ratio=1.0 → output length must equal input length $n, '
              'got ${result.length}');
    });

    test('ratio 2.0 returns double the input length', () {
      const n = 4410;
      final signal = Float64List(n)..fillRange(0, n, 0.5);
      final result = timeStretch(signal, 2.0);
      final expected = (n * 2.0).round();
      expect(result.length, equals(expected),
          reason: 'ratio=2.0 → output length must be $expected, '
              'got ${result.length}');
    });

    test('ratio 0.5 returns half the input length', () {
      const n = 8820; // 200 ms
      final signal = Float64List(n)..fillRange(0, n, 0.5);
      final result = timeStretch(signal, 0.5);
      final expected = (n * 0.5).round();
      expect(result.length, equals(expected),
          reason: 'ratio=0.5 → output length must be $expected, '
              'got ${result.length}');
    });

    test('all output samples are finite (no NaN or Inf)', () {
      const n = 2205; // 50 ms
      final signal = Float64List(n)..fillRange(0, n, 0.3);
      final result = timeStretch(signal, 1.5);
      for (int i = 0; i < result.length; i++) {
        expect(result[i].isFinite, isTrue,
            reason: 'output[$i] = ${result[i]} is not finite; '
                'NaN/Inf indicates a divide-by-zero or overflow in the phase vocoder');
      }
    });

    test('output amplitude stays within reasonable bounds for a unit-amplitude input', () {
      const n = 4410;
      final signal = Float64List(n)..fillRange(0, n, 1.0);
      final result = timeStretch(signal, 2.0);
      for (int i = 0; i < result.length; i++) {
        expect(result[i].abs(), lessThanOrEqualTo(2.0),
            reason: 'output[$i] = ${result[i]} exceeds ±2.0; '
                'the phase vocoder should not amplify a constant signal significantly');
      }
    });

    test('ratio 0.1 returns approximately 10× shorter output', () {
      const n = 44100; // 1 second
      final signal = Float64List(n)..fillRange(0, n, 0.5);
      final result = timeStretch(signal, 0.1);
      final expected = (n * 0.1).round();
      expect(result.length, equals(expected),
          reason: 'ratio=0.1 → output length must be $expected, '
              'got ${result.length}');
    });

    test('ratio 5.0 returns approximately 5× longer output', () {
      const n = 2205; // 50 ms — short enough to be fast in tests
      final signal = Float64List(n)..fillRange(0, n, 0.3);
      final result = timeStretch(signal, 5.0);
      final expected = (n * 5.0).round();
      expect(result.length, equals(expected),
          reason: 'ratio=5.0 → output length must be $expected, '
              'got ${result.length}');
    });
  });
}
