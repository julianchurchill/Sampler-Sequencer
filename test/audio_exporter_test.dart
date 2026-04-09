import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sampler_sequencer/audio/audio_exporter.dart';
import 'package:sampler_sequencer/audio/wav_io.dart';
import 'package:sampler_sequencer/audio/dsp_utils.dart';
import 'package:sampler_sequencer/constants.dart';

void main() {
  // -------------------------------------------------------------------------
  group('writeWavHeader', () {
    test('produces a 44-byte header', () {
      final header = writeWavHeader(
        numSamples: 1000,
        sampleRate: 44100,
        numChannels: 2,
      );
      expect(header.length, 44,
          reason: 'WAV header must be exactly 44 bytes; got ${header.length}');
    });

    test('starts with RIFF magic and contains WAVE marker', () {
      final header = writeWavHeader(
        numSamples: 100,
        sampleRate: 44100,
        numChannels: 2,
      );
      final str = String.fromCharCodes(header.sublist(0, 4));
      expect(str, 'RIFF',
          reason: 'WAV header bytes 0-3 must be "RIFF"; got "$str"');
      final wave = String.fromCharCodes(header.sublist(8, 12));
      expect(wave, 'WAVE',
          reason: 'WAV header bytes 8-11 must be "WAVE"; got "$wave"');
    });

    test('encodes correct data size for stereo', () {
      const numSamples = 500;
      const numChannels = 2;
      const expectedDataSize = numSamples * numChannels * 2; // 16-bit = 2 bytes
      final header = writeWavHeader(
        numSamples: numSamples,
        sampleRate: 44100,
        numChannels: numChannels,
      );
      final bd = ByteData.sublistView(header);
      final dataSize = bd.getUint32(40, Endian.little);
      expect(dataSize, expectedDataSize,
          reason: 'data chunk size at offset 40 should be '
              '$expectedDataSize (numSamples=$numSamples × numChannels=$numChannels × 2 bytes); '
              'got $dataSize');
    });

    test('encodes correct RIFF chunk size', () {
      const numSamples = 500;
      const numChannels = 1;
      const dataSize = numSamples * numChannels * 2;
      final header = writeWavHeader(
        numSamples: numSamples,
        sampleRate: 44100,
        numChannels: numChannels,
      );
      final bd = ByteData.sublistView(header);
      final riffSize = bd.getUint32(4, Endian.little);
      expect(riffSize, 36 + dataSize,
          reason: 'RIFF chunk size at offset 4 should be 36 + dataSize '
              '(${36 + dataSize}); got $riffSize');
    });

    test('encodes correct sample rate and byte rate', () {
      const sampleRate = 22050;
      const numChannels = 2;
      final header = writeWavHeader(
        numSamples: 100,
        sampleRate: sampleRate,
        numChannels: numChannels,
      );
      final bd = ByteData.sublistView(header);
      final encodedRate = bd.getUint32(24, Endian.little);
      expect(encodedRate, sampleRate,
          reason: 'sample rate at offset 24 should be $sampleRate; got $encodedRate');
      final byteRate = bd.getUint32(28, Endian.little);
      const expectedByteRate = sampleRate * numChannels * 2;
      expect(byteRate, expectedByteRate,
          reason: 'byte rate at offset 28 should be $expectedByteRate; got $byteRate');
    });

    test('encodes PCM format (audioFormat = 1)', () {
      final header = writeWavHeader(
        numSamples: 100,
        sampleRate: 44100,
        numChannels: 1,
      );
      final bd = ByteData.sublistView(header);
      final audioFormat = bd.getUint16(20, Endian.little);
      expect(audioFormat, 1,
          reason: 'audio format at offset 20 should be 1 (PCM); got $audioFormat');
    });
  });

  // -------------------------------------------------------------------------
  group('pcmChunkToBytes', () {
    test('converts Float64List chunk to Int16 bytes with correct values', () {
      // Simple case: [0.5, -0.5, 1.0, -1.0]
      final floats = Float64List.fromList([0.5, -0.5, 1.0, -1.0]);
      final bytes = pcmChunkToBytes(floats, 0, floats.length, 1.0);
      final bd = ByteData.sublistView(bytes);

      final s0 = bd.getInt16(0, Endian.little);
      expect(s0, (0.5 * 32767).round(),
          reason: 'sample 0 (0.5) should convert to ${(0.5 * 32767).round()}; got $s0');

      final s1 = bd.getInt16(2, Endian.little);
      expect(s1, (-0.5 * 32767).round(),
          reason: 'sample 1 (-0.5) should convert to ${(-0.5 * 32767).round()}; got $s1');

      final s2 = bd.getInt16(4, Endian.little);
      expect(s2, 32767,
          reason: 'sample 2 (1.0) should clamp to 32767; got $s2');

      final s3 = bd.getInt16(6, Endian.little);
      expect(s3, -32767,
          reason: 'sample 3 (-1.0) should convert to -32767; got $s3');
    });

    test('applies scale factor correctly', () {
      final floats = Float64List.fromList([1.0, -1.0]);
      final bytes = pcmChunkToBytes(floats, 0, floats.length, 0.5);
      final bd = ByteData.sublistView(bytes);

      final s0 = bd.getInt16(0, Endian.little);
      expect(s0, (0.5 * 32767).round(),
          reason: 'sample 0 (1.0 × scale 0.5) should be ${(0.5 * 32767).round()}; got $s0');
    });

    test('handles sub-range of buffer', () {
      final floats = Float64List.fromList([0.1, 0.2, 0.3, 0.4, 0.5]);
      // start=1, end=4 means indices 1, 2, 3 (3 samples)
      final bytes = pcmChunkToBytes(floats, 1, 4, 1.0);
      expect(bytes.length, 3 * 2,
          reason: 'sub-range of 3 samples (indices 1..3) should produce 6 bytes; got ${bytes.length}');
      final bd = ByteData.sublistView(bytes);
      final s0 = bd.getInt16(0, Endian.little);
      expect(s0, (0.2 * 32767).round(),
          reason: 'first sample in sub-range should be 0.2 scaled; got $s0');
    });

    test('produces output length of exactly (end - start) * 2 bytes', () {
      final floats = Float64List(1000);
      final bytes = pcmChunkToBytes(floats, 200, 700, 1.0);
      expect(bytes.length, 500 * 2,
          reason: 'chunk from index 200 to 700 should produce 1000 bytes; got ${bytes.length}');
    });
  });

  // -------------------------------------------------------------------------
  group('WAV round-trip via buildWav and readWav', () {
    test('mono WAV built by dsp_utils.buildWav round-trips through readWav', () async {
      // Generate a short known signal
      final samples = Float64List(512);
      for (int i = 0; i < samples.length; i++) {
        samples[i] = (i % 2 == 0) ? 0.5 : -0.5;
      }
      final wavBytes = buildWav(samples, 44100);

      // Write to temp file
      final tempDir = Directory.systemTemp.createTempSync('wav_test_');
      final tempFile = File('${tempDir.path}/test.wav');
      try {
        await tempFile.writeAsBytes(wavBytes);

        final wavData = await readWav(tempFile.path);
        expect(wavData, isNotNull,
            reason: 'readWav should successfully parse a WAV created by buildWav');
        expect(wavData!.sampleRate, 44100,
            reason: 'round-tripped sample rate should be 44100; got ${wavData.sampleRate}');
        expect(wavData.numChannels, 1,
            reason: 'buildWav produces mono; round-tripped numChannels should be 1; got ${wavData.numChannels}');
        expect(wavData.numFrames, samples.length,
            reason: 'round-tripped frame count should be ${samples.length}; got ${wavData.numFrames}');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('readWav returns null for non-WAV data', () async {
      final tempDir = Directory.systemTemp.createTempSync('wav_test_');
      final tempFile = File('${tempDir.path}/bad.wav');
      try {
        await tempFile.writeAsBytes([1, 2, 3, 4, 5]);
        final result = await readWav(tempFile.path);
        expect(result, isNull,
            reason: 'readWav should return null for data that is not a valid WAV');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('readWav returns null for missing file', () async {
      final result = await readWav('/tmp/nonexistent_wav_file_12345.wav');
      expect(result, isNull,
          reason: 'readWav should return null for a file path that does not exist');
    });

    test('readWav rejects bytes shorter than 44 (minimum WAV header)', () async {
      final tempDir = Directory.systemTemp.createTempSync('wav_test_');
      final tempFile = File('${tempDir.path}/short.wav');
      try {
        // Write 43 bytes — one less than the minimum WAV header
        await tempFile.writeAsBytes(List<int>.filled(43, 0));
        final result = await readWav(tempFile.path);
        expect(result, isNull,
            reason: 'readWav should return null for data shorter than 44 bytes (minimum WAV header size)');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('readWav rejects non-RIFF header', () async {
      final tempDir = Directory.systemTemp.createTempSync('wav_test_');
      final tempFile = File('${tempDir.path}/bad_riff.wav');
      try {
        // 44 bytes with wrong magic — "XXXX" instead of "RIFF"
        final bytes = Uint8List(44);
        bytes[0] = 0x58; // X
        bytes[1] = 0x58; // X
        bytes[2] = 0x58; // X
        bytes[3] = 0x58; // X
        await tempFile.writeAsBytes(bytes);
        final result = await readWav(tempFile.path);
        expect(result, isNull,
            reason: 'readWav should return null when bytes 0-3 are not "RIFF"');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('readWav rejects non-WAVE format marker', () async {
      final tempDir = Directory.systemTemp.createTempSync('wav_test_');
      final tempFile = File('${tempDir.path}/bad_wave.wav');
      try {
        // 44 bytes with correct RIFF but wrong format marker — "XXXX" instead of "WAVE"
        final bytes = Uint8List(44);
        // RIFF header
        bytes[0] = 0x52; // R
        bytes[1] = 0x49; // I
        bytes[2] = 0x46; // F
        bytes[3] = 0x46; // F
        // Wrong format marker at offset 8
        bytes[8] = 0x58; // X
        bytes[9] = 0x58; // X
        bytes[10] = 0x58; // X
        bytes[11] = 0x58; // X
        await tempFile.writeAsBytes(bytes);
        final result = await readWav(tempFile.path);
        expect(result, isNull,
            reason: 'readWav should return null when bytes 8-11 are not "WAVE"');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('peak normalization', () {
    test('when mix values exceed 1.0, output is clamped to 32767', () async {
      // Create a mix buffer where values exceed 1.0 (e.g., from summing
      // multiple tracks). The exporter must scale them so the final PCM
      // output stays within [-32768, 32767].
      const numFrames = 512;
      const numChannels = 1;
      final buf = Float64List(numFrames * numChannels);
      // Fill with values that exceed 1.0 — simulates overlapping loud tracks
      for (int i = 0; i < buf.length; i++) {
        buf[i] = 2.5; // well above 1.0
      }

      // Compute scale the same way the exporter does
      double peak = 0;
      for (final v in buf) {
        if (v.abs() > peak) peak = v.abs();
      }
      final scale = peak > 1.0 ? 1.0 / peak : 1.0;

      final tempDir = Directory.systemTemp.createTempSync('wav_norm_test_');
      final outputPath = '${tempDir.path}/normalized.wav';
      try {
        await writeWavChunked(
          outputPath: outputPath,
          mixBuffer: buf,
          scale: scale,
          sampleRate: 44100,
          numChannels: numChannels,
        );

        final wavData = await readWav(outputPath);
        expect(wavData, isNotNull,
            reason: 'writeWavChunked output should be parseable by readWav');
        for (int i = 0; i < wavData!.samples.length; i++) {
          expect(wavData.samples[i], lessThanOrEqualTo(32767),
              reason: 'normalized sample[$i] = ${wavData.samples[i]} should not exceed 32767');
          expect(wavData.samples[i], greaterThanOrEqualTo(-32768),
              reason: 'normalized sample[$i] = ${wavData.samples[i]} should not be below -32768');
        }
        // Additionally verify the peak is close to 32767 (full-scale after normalization)
        int maxSample = 0;
        for (final s in wavData.samples) {
          if (s.abs() > maxSample) maxSample = s.abs();
        }
        expect(maxSample, closeTo(32767, 1),
            reason: 'peak-normalized output should reach near full-scale (32767); got $maxSample');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('AudioExporter.export() output path validation', () {
    final dummySteps =
        List.generate(kNumTracks, (_) => List.filled(kNumSteps, false));
    final dummySamplePaths = List.filled(kNumTracks, '/tmp/nonexistent.wav');
    final dummyVolumes = List.filled(kNumTracks, 1.0);
    final dummyTrimStarts = List.filled(kNumTracks, Duration.zero);
    final dummyTrimEnds = List<Duration?>.filled(kNumTracks, null);

    test('throws ArgumentError when outputPath contains path traversal (..)', () {
      expect(
        AudioExporter.export(
          samplePaths: dummySamplePaths,
          volumes: dummyVolumes,
          trimStarts: dummyTrimStarts,
          trimEnds: dummyTrimEnds,
          steps: dummySteps,
          bpm: 120,
          numLoops: 1,
          outputPath: '/tmp/../etc/evil.wav',
        ),
        throwsA(isA<ArgumentError>()),
        reason: 'export() must reject outputPath values containing ".." to '
            'prevent path traversal — a caller must not be able to write '
            'outside the intended output directory',
      );
    });

    test('throws ArgumentError when outputPath does not end with .wav', () {
      expect(
        AudioExporter.export(
          samplePaths: dummySamplePaths,
          volumes: dummyVolumes,
          trimStarts: dummyTrimStarts,
          trimEnds: dummyTrimEnds,
          steps: dummySteps,
          bpm: 120,
          numLoops: 1,
          outputPath: '/tmp/export.exe',
        ),
        throwsA(isA<ArgumentError>()),
        reason: 'export() must reject outputPath values not ending with .wav — '
            'the function only writes WAV data and a non-.wav extension '
            'indicates a caller error or potential extension-confusion attack',
      );
    });

    test('does not throw for a valid outputPath and reports all nonexistent samples as unsupported', () async {
      final tempDir = Directory.systemTemp.createTempSync('exporter_test_');
      final outputPath = '${tempDir.path}/export_test.wav';
      try {
        // All steps off, so nothing is mixed, but all 4 sample paths are
        // nonexistent — export() loads every track regardless of step state,
        // so all 4 are reported as unsupported.  The test verifies the path
        // validation guard passes and the return value is correct.
        final unsupported = await AudioExporter.export(
          samplePaths: dummySamplePaths,
          volumes: dummyVolumes,
          trimStarts: dummyTrimStarts,
          trimEnds: dummyTrimEnds,
          steps: dummySteps,
          bpm: 120,
          numLoops: 1,
          outputPath: outputPath,
        );
        expect(unsupported, hasLength(kNumTracks),
            reason: 'all $kNumTracks dummy sample paths are nonexistent, so '
                'every track should be reported as unsupported');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('chunked WAV write produces identical output to monolithic write', () {
    test('writeWavChunked produces a valid WAV identical to monolithic approach', () async {
      // Build a mix buffer with known values
      const numFrames = 4096;
      const numChannels = 2;
      final buf = Float64List(numFrames * numChannels);
      for (int i = 0; i < buf.length; i++) {
        buf[i] = (i / buf.length) * 2.0 - 1.0; // linear ramp -1 to +1
      }

      // Compute scale (same as export does)
      double peak = 0;
      for (final v in buf) {
        if (v.abs() > peak) peak = v.abs();
      }
      final scale = peak > 1.0 ? 1.0 / peak : 1.0;

      final tempDir = Directory.systemTemp.createTempSync('wav_chunk_test_');
      final outputPath = '${tempDir.path}/chunked.wav';
      try {
        await writeWavChunked(
          outputPath: outputPath,
          mixBuffer: buf,
          scale: scale,
          sampleRate: 44100,
          numChannels: numChannels,
        );

        // Read back and verify
        final wavData = await readWav(outputPath);
        expect(wavData, isNotNull,
            reason: 'writeWavChunked output should be parseable by readWav');
        expect(wavData!.sampleRate, 44100,
            reason: 'chunked WAV sample rate should be 44100; got ${wavData.sampleRate}');
        expect(wavData.numChannels, numChannels,
            reason: 'chunked WAV numChannels should be $numChannels; got ${wavData.numChannels}');
        expect(wavData.numFrames, numFrames,
            reason: 'chunked WAV should have $numFrames frames; got ${wavData.numFrames}');

        // Verify sample values match expected PCM conversion
        // Check first few samples
        for (int i = 0; i < 10; i++) {
          final expected = (buf[i] * scale * 32767).round().clamp(-32768, 32767);
          expect(wavData.samples[i], expected,
              reason: 'chunked WAV sample[$i]: expected $expected, got ${wavData.samples[i]}');
        }
        // Check last few samples
        for (int i = wavData.samples.length - 10; i < wavData.samples.length; i++) {
          final expected = (buf[i] * scale * 32767).round().clamp(-32768, 32767);
          expect(wavData.samples[i], expected,
              reason: 'chunked WAV sample[$i]: expected $expected, got ${wavData.samples[i]}');
        }
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
