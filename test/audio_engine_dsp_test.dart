import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sampler_sequencer/audio/dsp_utils.dart';

const int _kSampleRate = 44100;

void main() {
  // -------------------------------------------------------------------------
  group('buildWav', () {
    test('output length is 44 + numSamples * 2', () {
      final samples = Float64List(100);
      final wav = buildWav(samples, _kSampleRate);
      expect(wav.length, 44 + 100 * 2);
    });

    test('starts with RIFF magic bytes', () {
      final wav = buildWav(Float64List(0), _kSampleRate);
      expect(wav[0], 0x52); // R
      expect(wav[1], 0x49); // I
      expect(wav[2], 0x46); // F
      expect(wav[3], 0x46); // F
    });

    test('contains WAVE marker at offset 8', () {
      final wav = buildWav(Float64List(0), _kSampleRate);
      expect(wav[8],  0x57); // W
      expect(wav[9],  0x41); // A
      expect(wav[10], 0x56); // V
      expect(wav[11], 0x45); // E
    });

    test('contains fmt  marker at offset 12', () {
      final wav = buildWav(Float64List(0), _kSampleRate);
      expect(wav[12], 0x66); // f
      expect(wav[13], 0x6D); // m
      expect(wav[14], 0x74); // t
      expect(wav[15], 0x20); // (space)
    });

    test('contains data marker at offset 36', () {
      final wav = buildWav(Float64List(0), _kSampleRate);
      expect(wav[36], 0x64); // d
      expect(wav[37], 0x61); // a
      expect(wav[38], 0x74); // t
      expect(wav[39], 0x61); // a
    });
  });

  // -------------------------------------------------------------------------
  group('dspEnv', () {
    test('returns 1.0 at i=0', () {
      expect(dspEnv(0, 100, 4.0), closeTo(1.0, 1e-10));
    });

    test('returns a value near zero at end of envelope', () {
      expect(dspEnv(100, 100, 4.0), lessThan(0.02));
    });

    test('is monotonically decreasing', () {
      final vals = List.generate(50, (i) => dspEnv(i, 100, 4.0));
      for (int i = 1; i < vals.length; i++) {
        expect(vals[i], lessThan(vals[i - 1]));
      }
    });
  });

  // -------------------------------------------------------------------------
  group('drum generators', () {
    test('generateKick808 returns expected number of samples', () {
      // 500 ms at 44100 Hz = 22050 samples
      final buf = generateKick808(_kSampleRate);
      expect(buf.length, _kSampleRate * 500 ~/ 1000);
    });

    test('generateSnare all samples are in [-1.0, 1.0]', () {
      final buf = generateSnare(_kSampleRate);
      for (final sample in buf) {
        expect(sample, inInclusiveRange(-1.0, 1.0));
      }
    });

    test('generateKickHard returns expected number of samples', () {
      // 300 ms
      final buf = generateKickHard(_kSampleRate);
      expect(buf.length, _kSampleRate * 300 ~/ 1000);
    });

    test('generateHiHatClosed returns expected number of samples', () {
      // 80 ms
      final buf = generateHiHatClosed(_kSampleRate);
      expect(buf.length, _kSampleRate * 80 ~/ 1000);
    });

    test('generateCowbell returns expected number of samples', () {
      // 800 ms
      final buf = generateCowbell(_kSampleRate);
      expect(buf.length, _kSampleRate * 800 ~/ 1000);
    });

    test('generateKick808 all samples are in [-1.0, 1.0]', () {
      final buf = generateKick808(_kSampleRate);
      for (final sample in buf) {
        expect(sample, inInclusiveRange(-1.0, 1.0));
      }
    });
  });
}
