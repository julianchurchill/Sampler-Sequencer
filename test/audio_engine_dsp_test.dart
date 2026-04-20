import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sampler_sequencer/audio/dsp_utils.dart';
import 'package:sampler_sequencer/audio/wav_io.dart';

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
  group('buildWav fade envelope', () {
    // Build a WAV from a constant +1.0 signal so that any fade multiplier is
    // directly visible in the encoded PCM values.
    const int n = 2000; // longer than 2 × kWavFadeSamples
    final constantSamples = Float64List(n)..fillRange(0, n, 1.0);

    final wav = buildWav(constantSamples, _kSampleRate);
    final pcm = ByteData.sublistView(wav);

    int readPcm(int sampleIndex) =>
        pcm.getInt16(44 + sampleIndex * 2, Endian.little);

    test('first PCM sample is silent (fade-in starts at zero)', () {
      expect(readPcm(0), 0,
          reason: 'buildWav fade-in: sample[0] should be 0 — a non-zero first '
              'sample causes an audible click when playback starts after silence');
    });

    test('last PCM sample is silent (fade-out ends at zero)', () {
      expect(readPcm(n - 1), 0,
          reason: 'buildWav fade-out: sample[${n - 1}] should be 0 — a non-zero '
              'final sample causes an audible click when the file ends or loops');
    });

    test('mid-point sample is at full amplitude (fade region does not reach centre)', () {
      final mid = readPcm(n ~/ 2);
      expect(mid, closeTo(32767, 1),
          reason: 'buildWav: sample[${n ~/ 2}] should be ~32767 — fade regions '
              'must not reach the centre of a signal longer than 2×kWavFadeSamples');
    });

    test('fade-in is monotonically non-decreasing across the first kWavFadeSamples', () {
      for (int i = 1; i < kWavFadeSamples; i++) {
        final prev = readPcm(i - 1);
        final curr = readPcm(i);
        expect(curr, greaterThanOrEqualTo(prev),
            reason: 'buildWav fade-in: PCM sample[$i] = $curr should be '
                '>= sample[${i - 1}] = $prev — fade-in must increase monotonically');
      }
    });

    test('fade-out is monotonically non-increasing across the last kWavFadeSamples', () {
      for (int i = n - kWavFadeSamples + 1; i < n; i++) {
        final prev = readPcm(i - 1);
        final curr = readPcm(i);
        expect(curr, lessThanOrEqualTo(prev),
            reason: 'buildWav fade-out: PCM sample[$i] = $curr should be '
                '<= sample[${i - 1}] = $prev — fade-out must decrease monotonically');
      }
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

    test('is strictly monotonically decreasing over its full range', () {
      for (int i = 1; i < 100; i++) {
        final prev = dspEnv(i - 1, 100, 4.0);
        final curr = dspEnv(i, 100, 4.0);
        expect(curr, lessThan(prev),
            reason: 'dspEnv($i) = $curr should be less than dspEnv(${i - 1}) = $prev — '
                'envelope must decay monotonically at every sample (i=$i)');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('extractWaveformPeaks', () {
    test('empty samples returns zero-filled bins', () {
      final peaks = extractWaveformPeaks(Int16List(0), 1, 4);
      expect(peaks.length, equals(4),
          reason: 'should return numBins values even for empty input');
      for (int i = 0; i < peaks.length; i++) {
        expect(peaks[i], equals(0.0),
            reason: 'bin $i should be 0.0 for empty samples');
      }
    });

    test('zero numBins returns empty list', () {
      final peaks = extractWaveformPeaks(Int16List.fromList([32767]), 1, 0);
      expect(peaks.length, equals(0),
          reason: 'zero bins requested → empty result');
    });

    test('single channel: absolute peak per bin normalized 0–1', () {
      // 4 frames, 4 bins → 1 frame per bin
      final samples = Int16List.fromList([0, 32767, -32767, 16384]);
      final peaks = extractWaveformPeaks(samples, 1, 4);
      expect(peaks.length, equals(4), reason: 'one bin per frame');
      expect(peaks[0], closeTo(0.0, 0.001),
          reason: 'bin 0: sample is 0 → peak 0.0');
      expect(peaks[1], closeTo(1.0, 0.001),
          reason: 'bin 1: max positive Int16 value → peak 1.0');
      expect(peaks[2], closeTo(1.0, 0.001),
          reason: 'bin 2: max negative abs maps to peak 1.0');
      expect(peaks[3], closeTo(0.5, 0.002),
          reason: 'bin 3: 16384/32767 ≈ 0.5');
    });

    test('stereo: peak is max absolute amplitude across channels', () {
      // 1 stereo frame: L=0, R=32767 → peak should be 1.0
      final samples = Int16List.fromList([0, 32767]);
      final peaks = extractWaveformPeaks(samples, 2, 1);
      expect(peaks[0], closeTo(1.0, 0.001),
          reason: 'should take max from right channel (R=32767)');
    });

    test('more bins than frames: all bins are in valid range 0–1', () {
      final samples = Int16List.fromList([16384, 16384]);
      final peaks = extractWaveformPeaks(samples, 1, 8);
      expect(peaks.length, equals(8), reason: 'should return numBins values');
      for (int i = 0; i < peaks.length; i++) {
        expect(peaks[i], inInclusiveRange(0.0, 1.0),
            reason: 'bin $i value ${peaks[i]} should be in [0.0, 1.0]');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('readWavDuration', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('wav_duration_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    Future<String> writeTestWav({
      required int numFrames,
      required int sampleRate,
      required int numChannels,
    }) async {
      final path = '${tempDir.path}/test_${numFrames}_${sampleRate}_$numChannels.wav';
      final header = writeWavHeader(
        numSamples: numFrames,
        sampleRate: sampleRate,
        numChannels: numChannels,
      );
      final pcm = Uint8List(numFrames * numChannels * 2); // silent PCM data
      await File(path).writeAsBytes([...header, ...pcm]);
      return path;
    }

    test('returns correct duration for a 5-second mono WAV', () async {
      final path = await writeTestWav(
        numFrames: 5 * 44100,
        sampleRate: 44100,
        numChannels: 1,
      );
      final dur = await readWavDuration(path);
      expect(dur, isNotNull,
          reason: 'should parse a valid 5-second mono WAV header');
      expect(dur!.inMilliseconds, closeTo(5000, 5),
          reason: 'mono WAV: 5 × 44100 frames / 44100 Hz = exactly 5 s');
    });

    test('returns correct duration for a 500 ms stereo WAV', () async {
      final path = await writeTestWav(
        numFrames: 44100 ~/ 2,
        sampleRate: 44100,
        numChannels: 2,
      );
      final dur = await readWavDuration(path);
      expect(dur, isNotNull,
          reason: 'should parse a valid 500 ms stereo WAV header');
      expect(dur!.inMilliseconds, closeTo(500, 5),
          reason: 'stereo WAV: 22050 frames / 44100 Hz = 0.5 s');
    });

    test('returns correct duration for a non-standard sample rate', () async {
      final path = await writeTestWav(
        numFrames: 3 * 22050,
        sampleRate: 22050,
        numChannels: 1,
      );
      final dur = await readWavDuration(path);
      expect(dur, isNotNull,
          reason: 'should parse a 22050 Hz WAV header');
      expect(dur!.inMilliseconds, closeTo(3000, 5),
          reason: '22050 Hz WAV: 3 × 22050 frames / 22050 Hz = 3 s');
    });

    test('returns null for a non-existent file', () async {
      final dur = await readWavDuration('${tempDir.path}/no_such_file.wav');
      expect(dur, isNull,
          reason: 'should return null when the file does not exist');
    });

    test('returns null for a file containing garbage bytes', () async {
      final path = '${tempDir.path}/garbage.bin';
      await File(path).writeAsBytes([0, 1, 2, 3, 4, 5, 6, 7]);
      final dur = await readWavDuration(path);
      expect(dur, isNull,
          reason: 'should return null for a file with no RIFF/WAVE header');
    });

    test('returns null for a file shorter than 44 bytes', () async {
      final path = '${tempDir.path}/tiny.wav';
      await File(path).writeAsBytes(Uint8List(20));
      final dur = await readWavDuration(path);
      expect(dur, isNull,
          reason: 'should return null for a file too short to hold a WAV header');
    });
  });

  // -------------------------------------------------------------------------
  group('drum generators', () {
    test('generateKick808 produces the expected number of samples (500 ms)', () {
      final buf = generateKick808(_kSampleRate);
      const expected = _kSampleRate * 500 ~/ 1000;
      expect(buf.length, expected,
          reason: 'Kick 808 is 500 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateKickHard produces the expected number of samples (300 ms)', () {
      final buf = generateKickHard(_kSampleRate);
      const expected = _kSampleRate * 300 ~/ 1000;
      expect(buf.length, expected,
          reason: 'Kick Hard is 300 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateHiHatClosed produces the expected number of samples (80 ms)', () {
      final buf = generateHiHatClosed(_kSampleRate);
      const expected = _kSampleRate * 80 ~/ 1000;
      expect(buf.length, expected,
          reason: 'HH Closed is 80 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateCowbell produces the expected number of samples (800 ms)', () {
      final buf = generateCowbell(_kSampleRate);
      const expected = _kSampleRate * 800 ~/ 1000;
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

    test('sixteen Kick808 streams at 120-BPM 16th-note steps do not clip', () {
      // Sixteen Kick808 hits on consecutive 16th-note steps (125 ms apart at
      // 120 BPM) produce up to 4 simultaneous streams in the SoundPool mixer
      // (the kick is 500 ms long). If their combined amplitude ever exceeds 1.0
      // the mixer hard-clips, producing an audible crack. This is the full
      // worst-case bar of kicks — a stronger version of the 2-stream check.
      //
      // The amplitude 0.9 → 0.72 reduction was introduced to fix this. If the
      // amplitude is ever raised again, this test will catch the regression.
      final buf = generateKick808(_kSampleRate);
      const stepSamples = _kSampleRate * 125 ~/ 1000; // 120 BPM = 125 ms/step
      const steps = 16;
      // Scan the full window including the tail of the 16th kick.
      final totalSamples = buf.length + (steps - 1) * stepSamples;
      for (int i = 0; i < totalSamples; i++) {
        double combined = 0.0;
        for (int step = 0; step < steps; step++) {
          final bufIdx = i - step * stepSamples;
          if (bufIdx >= 0 && bufIdx < buf.length) {
            combined += buf[bufIdx];
          }
        }
        expect(combined.abs(), lessThanOrEqualTo(1.0),
            reason: 'generateKick808: 16-step mix clips at sample $i '
                '(combined=$combined). Hard PCM clipping in the SoundPool mixer '
                'causes an audible click. Do not raise the Kick808 amplitude '
                'above 0.72 without verifying this test still passes.');
      }
    });

    test('generateKick808 peak amplitude is above the audibility threshold', () {
      // Guards against the amplitude being reduced so far that the kick becomes
      // inaudible. Anything below ~0.3 would be lost in a mix.
      final buf = generateKick808(_kSampleRate);
      final peak = buf.map((s) => s.abs()).reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThan(0.3),
          reason: 'generateKick808 peak amplitude $peak is below 0.3 — the kick '
              'would be inaudible in a mix. Do not reduce the amplitude multiplier '
              'below ~0.72.');
    });

    test('generateRimShot produces the expected number of samples (120 ms)', () {
      final buf = generateRimShot(_kSampleRate);
      const expected = _kSampleRate * 120 ~/ 1000;
      expect(buf.length, expected,
          reason: 'Rim Shot is 120 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateRimShot all samples are within the normalised range [-1.0, 1.0]', () {
      final buf = generateRimShot(_kSampleRate);
      for (int i = 0; i < buf.length; i++) {
        expect(buf[i], inInclusiveRange(-1.0, 1.0),
            reason: 'generateRimShot: sample[$i] = ${buf[i]} is outside [-1.0, 1.0] — would clip when converting to 16-bit PCM');
      }
    });

    test('generateHiHatOpen produces the expected number of samples (600 ms)', () {
      final buf = generateHiHatOpen(_kSampleRate);
      const expected = _kSampleRate * 600 ~/ 1000;
      expect(buf.length, expected,
          reason: 'HH Open is 600 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateHiHatOpen all samples are within the normalised range [-1.0, 1.0]', () {
      final buf = generateHiHatOpen(_kSampleRate);
      for (int i = 0; i < buf.length; i++) {
        expect(buf[i], inInclusiveRange(-1.0, 1.0),
            reason: 'generateHiHatOpen: sample[$i] = ${buf[i]} is outside [-1.0, 1.0] — would clip when converting to 16-bit PCM');
      }
    });

    test('generateClap produces the expected number of samples (220 ms)', () {
      final buf = generateClap(_kSampleRate);
      const expected = _kSampleRate * 220 ~/ 1000;
      expect(buf.length, expected,
          reason: 'Clap is 220 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateClap all samples are within the normalised range [-1.0, 1.0]', () {
      final buf = generateClap(_kSampleRate);
      for (int i = 0; i < buf.length; i++) {
        expect(buf[i], inInclusiveRange(-1.0, 1.0),
            reason: 'generateClap: sample[$i] = ${buf[i]} is outside [-1.0, 1.0] — would clip when converting to 16-bit PCM');
      }
    });

    test('generateTom produces the expected number of samples (400 ms)', () {
      final buf = generateTom(_kSampleRate);
      const expected = _kSampleRate * 400 ~/ 1000;
      expect(buf.length, expected,
          reason: 'Tom is 400 ms — expected $expected samples at $_kSampleRate Hz, got ${buf.length}');
    });

    test('generateTom all samples are within the normalised range [-1.0, 1.0]', () {
      final buf = generateTom(_kSampleRate);
      for (int i = 0; i < buf.length; i++) {
        expect(buf[i], inInclusiveRange(-1.0, 1.0),
            reason: 'generateTom: sample[$i] = ${buf[i]} is outside [-1.0, 1.0] — would clip when converting to 16-bit PCM');
      }
    });
  });
}
