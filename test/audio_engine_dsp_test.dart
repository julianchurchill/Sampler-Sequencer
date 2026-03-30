import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sampler_sequencer/audio/dsp_utils.dart';

const int _kSampleRate = 44100;

void main() {
  // -------------------------------------------------------------------------
  group('buildWav', () {
    test('output length is 44-byte header plus 2 bytes per sample', () {
      final samples = Float64List(100);
      final wav = buildWav(samples, _kSampleRate);
      expect(wav.length, 44 + 100 * 2,
          reason: 'WAV = 44-byte header + (numSamples × 2 bytes for 16-bit PCM); got ${wav.length}');
    });

    test('starts with RIFF magic bytes', () {
      final wav = buildWav(Float64List(0), _kSampleRate);
      expect(wav[0], 0x52, reason: 'byte 0 should be R (0x52)');
      expect(wav[1], 0x49, reason: 'byte 1 should be I (0x49)');
      expect(wav[2], 0x46, reason: 'byte 2 should be F (0x46)');
      expect(wav[3], 0x46, reason: 'byte 3 should be F (0x46)');
    });

    test('contains WAVE marker at offset 8', () {
      final wav = buildWav(Float64List(0), _kSampleRate);
      expect(wav[8],  0x57, reason: 'byte 8 should be W (0x57)');
      expect(wav[9],  0x41, reason: 'byte 9 should be A (0x41)');
      expect(wav[10], 0x56, reason: 'byte 10 should be V (0x56)');
      expect(wav[11], 0x45, reason: 'byte 11 should be E (0x45)');
    });

    test('contains fmt\\x20 chunk marker at offset 12', () {
      final wav = buildWav(Float64List(0), _kSampleRate);
      expect(wav[12], 0x66, reason: 'byte 12 should be f (0x66)');
      expect(wav[13], 0x6D, reason: 'byte 13 should be m (0x6D)');
      expect(wav[14], 0x74, reason: 'byte 14 should be t (0x74)');
      expect(wav[15], 0x20, reason: 'byte 15 should be space (0x20)');
    });

    test('contains data chunk marker at offset 36', () {
      final wav = buildWav(Float64List(0), _kSampleRate);
      expect(wav[36], 0x64, reason: 'byte 36 should be d (0x64)');
      expect(wav[37], 0x61, reason: 'byte 37 should be a (0x61)');
      expect(wav[38], 0x74, reason: 'byte 38 should be t (0x74)');
      expect(wav[39], 0x61, reason: 'byte 39 should be a (0x61)');
    });
  });

  // -------------------------------------------------------------------------
  group('dspEnv', () {
    test('returns exactly 1.0 at i=0 (start of envelope)', () {
      expect(dspEnv(0, 100, 4.0), closeTo(1.0, 1e-10),
          reason: 'Envelope should be at full amplitude (1.0) at the start (i=0)');
    });

    test('returns near zero at the end of the envelope', () {
      expect(dspEnv(100, 100, 4.0), lessThan(0.02),
          reason: 'Envelope with decayRate=4.0 should decay to near zero by i=totalSamples');
    });

    test('is strictly monotonically decreasing over its range', () {
      for (int i = 1; i < 50; i++) {
        final prev = dspEnv(i - 1, 100, 4.0);
        final curr = dspEnv(i, 100, 4.0);
        expect(curr, lessThan(prev),
            reason: 'dspEnv($i) = $curr should be less than dspEnv(${i - 1}) = $prev — envelope must decay monotonically');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('drum generators', () {
    test('generateKick808 produces the expected number of samples (500 ms)', () {
      final buf = generateKick808(_kSampleRate);
      final expected = _kSampleRate * 500 ~/ 1000;
      expect(buf.length, expected,
          reason: 'Kick 808 is 500 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateKickHard produces the expected number of samples (300 ms)', () {
      final buf = generateKickHard(_kSampleRate);
      final expected = _kSampleRate * 300 ~/ 1000;
      expect(buf.length, expected,
          reason: 'Kick Hard is 300 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateHiHatClosed produces the expected number of samples (80 ms)', () {
      final buf = generateHiHatClosed(_kSampleRate);
      final expected = _kSampleRate * 80 ~/ 1000;
      expect(buf.length, expected,
          reason: 'HH Closed is 80 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateCowbell produces the expected number of samples (800 ms)', () {
      final buf = generateCowbell(_kSampleRate);
      final expected = _kSampleRate * 800 ~/ 1000;
      expect(buf.length, expected,
          reason: 'Cowbell is 800 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateKick808 all samples are within the normalised range [-1.0, 1.0]', () {
      final buf = generateKick808(_kSampleRate);
      for (int i = 0; i < buf.length; i++) {
        expect(buf[i], inInclusiveRange(-1.0, 1.0),
            reason: 'generateKick808: sample[$i] = ${buf[i]} is outside [-1.0, 1.0] — would clip when converting to 16-bit PCM');
      }
    });

    test('generateSnare all samples are within the normalised range [-1.0, 1.0]', () {
      final buf = generateSnare(_kSampleRate);
      for (int i = 0; i < buf.length; i++) {
        expect(buf[i], inInclusiveRange(-1.0, 1.0),
            reason: 'generateSnare: sample[$i] = ${buf[i]} is outside [-1.0, 1.0] — would clip when converting to 16-bit PCM');
      }
    });
  });
}
