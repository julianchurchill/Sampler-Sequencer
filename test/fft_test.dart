import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sampler_sequencer/audio/fft.dart';

void main() {
  // -------------------------------------------------------------------------
  group('fft / ifft', () {
    test('round-trip: ifft(fft(x)) recovers x to floating-point precision', () {
      const n = 8;
      final re = Float64List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final im = Float64List(n);
      final origRe = Float64List.fromList(re);
      fft(re, im);
      ifft(re, im);
      for (int i = 0; i < n; i++) {
        expect(re[i], closeTo(origRe[i], 1e-9),
            reason: 'round-trip: re[$i] should recover to ${origRe[i]} '
                'but got ${re[i]}');
        expect(im[i], closeTo(0.0, 1e-9),
            reason: 'round-trip: im[$i] should be ~0 after ifft(fft(real signal)) '
                'but got ${im[i]}');
      }
    });

    test('impulse at 0 has flat magnitude spectrum (all bins = 1.0)', () {
      const n = 16;
      final re = Float64List(n);
      final im = Float64List(n);
      re[0] = 1.0;
      fft(re, im);
      for (int k = 0; k < n; k++) {
        final mag = math.sqrt(re[k] * re[k] + im[k] * im[k]);
        expect(mag, closeTo(1.0, 1e-9),
            reason: 'FFT of unit impulse at 0: bin $k magnitude should be 1.0, '
                'got $mag');
      }
    });

    test('DC signal (all ones) has energy only in bin 0', () {
      const n = 16;
      final re = Float64List(n)..fillRange(0, n, 1.0);
      final im = Float64List(n);
      fft(re, im);
      expect(re[0], closeTo(n.toDouble(), 1e-9),
          reason: 'DC: re[0] should be N=$n, got ${re[0]}');
      expect(im[0], closeTo(0.0, 1e-9),
          reason: 'DC: im[0] should be 0, got ${im[0]}');
      for (int k = 1; k < n; k++) {
        final mag = math.sqrt(re[k] * re[k] + im[k] * im[k]);
        expect(mag, closeTo(0.0, 1e-9),
            reason: 'DC: bin $k should be ~0, got magnitude $mag');
      }
    });

    test('Parseval: sum of squared magnitudes equals N × input energy', () {
      const n = 32;
      final re = Float64List.fromList(
          List.generate(n, (i) => math.sin(2 * math.pi * 3 * i / n)));
      final im = Float64List(n);
      final inputEnergy = re.fold(0.0, (e, x) => e + x * x);
      fft(re, im);
      final spectrumEnergy =
          List.generate(n, (k) => re[k] * re[k] + im[k] * im[k])
              .fold(0.0, (e, x) => e + x);
      expect(spectrumEnergy, closeTo(n * inputEnergy, 1e-6),
          reason: 'Parseval: sum |X[k]|² = N × sum |x[n]|²; '
              'got spectrum=$spectrumEnergy, expected=${n * inputEnergy}');
    });
  });
}
