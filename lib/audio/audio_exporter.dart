import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Decoded PCM data from a WAV file.
class WavData {
  WavData({
    required this.sampleRate,
    required this.numChannels,
    required this.samples,
  });

  final int sampleRate;
  final int numChannels;

  /// Raw 16-bit signed PCM samples, interleaved for stereo.
  final Int16List samples;

  int get numFrames => samples.length ~/ numChannels;
}

/// Build a 44-byte WAV header for 16-bit PCM data.
///
/// [numSamples] is the total number of sample values (frames × channels).
@visibleForTesting
Uint8List writeWavHeader({
  required int numSamples,
  required int sampleRate,
  required int numChannels,
}) {
  final dataSize = numSamples * numChannels * 2;
  final hdr = ByteData(44);

  void setFourCC(int offset, String s) {
    for (int i = 0; i < 4; i++) {
      hdr.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  setFourCC(0, 'RIFF');
  hdr.setUint32(4, 36 + dataSize, Endian.little);
  setFourCC(8, 'WAVE');
  setFourCC(12, 'fmt ');
  hdr.setUint32(16, 16, Endian.little);        // fmt chunk size
  hdr.setUint16(20, 1, Endian.little);         // PCM
  hdr.setUint16(22, numChannels, Endian.little);
  hdr.setUint32(24, sampleRate, Endian.little);
  hdr.setUint32(28, sampleRate * numChannels * 2, Endian.little); // byte rate
  hdr.setUint16(32, numChannels * 2, Endian.little);              // block align
  hdr.setUint16(34, 16, Endian.little);        // bits per sample
  setFourCC(36, 'data');
  hdr.setUint32(40, dataSize, Endian.little);

  return hdr.buffer.asUint8List();
}

/// Convert a sub-range of a Float64List mix buffer to little-endian Int16 bytes.
///
/// Returns a Uint8List of length (end - start) * 2.
/// Both Android and iOS are little-endian, matching the WAV spec, so we can
/// write the Int16List backing buffer directly without per-sample setInt16.
@visibleForTesting
Uint8List pcmChunkToBytes(Float64List buf, int start, int end, double scale) {
  final count = end - start;
  final pcm = Int16List(count);
  for (int i = 0; i < count; i++) {
    pcm[i] = (buf[start + i] * scale * 32767).round().clamp(-32768, 32767);
  }
  return pcm.buffer.asUint8List();
}

/// Write a WAV file in chunks, avoiding holding both Float64List and full
/// Int16List simultaneously.
///
/// Instead of allocating a full Int16List copy of the mix buffer, this streams
/// the PCM conversion in chunks of [_kChunkSamples] samples, keeping peak
/// memory close to the Float64List size alone.
@visibleForTesting
Future<void> writeWavChunked({
  required String outputPath,
  required Float64List mixBuffer,
  required double scale,
  required int sampleRate,
  required int numChannels,
}) async {
  const chunkSamples = 8192;
  final totalSamples = mixBuffer.length;
  final numFrames = totalSamples ~/ numChannels;

  final header = writeWavHeader(
    numSamples: numFrames,
    sampleRate: sampleRate,
    numChannels: numChannels,
  );

  final file = File(outputPath);
  final sink = file.openWrite();
  sink.add(header);

  for (int offset = 0; offset < totalSamples; offset += chunkSamples) {
    final end = (offset + chunkSamples).clamp(0, totalSamples);
    sink.add(pcmChunkToBytes(mixBuffer, offset, end, scale));
  }

  await sink.close();
}

/// Parse a WAV file into PCM frames.
/// Returns null if the file is missing, not a WAV, or not PCM format.
@visibleForTesting
Future<WavData?> readWav(String path) async {
  return AudioExporter._readWav(path);
}

/// Offline renderer: reads each track's WAV file, mixes them at the correct
/// step-sequence timing, and writes a stereo 44100 Hz 16-bit WAV.
class AudioExporter {
  static const int _kSampleRate = 44100;
  static const int _kNumChannels = 2; // stereo output
  static const double _kStepsPerQuarterNote = 4.0;

  /// Parse a WAV file into PCM frames.
  /// Returns null if the file is missing, not a WAV, or not PCM format.
  static Future<WavData?> _readWav(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.length < 44) return null;

      final asString = (List<int> b) => String.fromCharCodes(b);
      if (asString(bytes.sublist(0, 4)) != 'RIFF') return null;
      if (asString(bytes.sublist(8, 12)) != 'WAVE') return null;

      int? audioFormat, numChannels, sampleRate, bitsPerSample;
      int? dataOffset, dataSize;

      int i = 12;
      while (i + 8 <= bytes.length) {
        final chunkId = asString(bytes.sublist(i, i + 4));
        final bd = ByteData.sublistView(bytes, i + 4, i + 8);
        final chunkSize = bd.getUint32(0, Endian.little);

        if (chunkId == 'fmt ') {
          final fmt = ByteData.sublistView(bytes, i + 8, i + 8 + chunkSize);
          audioFormat = fmt.getUint16(0, Endian.little);
          numChannels = fmt.getUint16(2, Endian.little);
          sampleRate = fmt.getUint32(4, Endian.little);
          bitsPerSample = fmt.getUint16(14, Endian.little);
        } else if (chunkId == 'data') {
          dataOffset = i + 8;
          dataSize = chunkSize;
          break; // data chunk found; stop walking
        }

        // Chunks are word-aligned.
        i += 8 + chunkSize + (chunkSize & 1);
      }

      if (audioFormat != 1) return null; // must be PCM
      if (numChannels == null || sampleRate == null || bitsPerSample == null) return null;
      if (dataOffset == null || dataSize == null) return null;

      final clampedSize = dataSize.clamp(0, bytes.length - dataOffset);
      final bytesPerSample = bitsPerSample ~/ 8;
      final numSamples = clampedSize ~/ bytesPerSample;
      final out = Int16List(numSamples);
      final view = ByteData.sublistView(bytes, dataOffset, dataOffset + clampedSize);

      if (bitsPerSample == 16) {
        for (int j = 0; j < numSamples; j++) {
          out[j] = view.getInt16(j * 2, Endian.little);
        }
      } else if (bitsPerSample == 8) {
        // 8-bit WAV is unsigned; convert to signed 16-bit.
        for (int j = 0; j < numSamples; j++) {
          out[j] = ((view.getUint8(j) - 128) << 8).clamp(-32768, 32767);
        }
      } else {
        return null; // unsupported bit depth
      }

      return WavData(
        sampleRate: sampleRate,
        numChannels: numChannels,
        samples: out,
      );
    } catch (e) {
      debugPrint('AudioExporter _readWav error: $e');
      return null;
    }
  }

  /// Mix and export [numLoops] passes of the sequence to a 16-bit stereo WAV
  /// at [outputPath].
  ///
  /// [samplePaths] — resolved path for each of the 4 tracks.
  /// [unsupportedTracks] — output list filled with indices of tracks that
  ///   had non-WAV files and were silenced in the mix.
  /// [onProgress] — optional callback, value in 0.0–1.0.
  static Future<void> export({
    required List<String> samplePaths,
    required List<double> volumes,
    required List<Duration> trimStarts,
    required List<Duration?> trimEnds,
    required List<List<bool>> steps,
    required int bpm,
    required int numLoops,
    required String outputPath,
    required List<int> unsupportedTracks,
    void Function(double)? onProgress,
  }) async {
    const numTracks = 4;
    const numSteps = 16;

    // ── Load WAV data for every track ───────────────────────────────────────
    final trackData = List<WavData?>.filled(numTracks, null);
    for (int t = 0; t < numTracks; t++) {
      final wav = await _readWav(samplePaths[t]);
      if (wav == null) {
        unsupportedTracks.add(t);
      } else {
        trackData[t] = wav;
      }
    }

    // ── Compute timeline ────────────────────────────────────────────────────
    final stepFrames = (_kSampleRate * 60.0 / (bpm * _kStepsPerQuarterNote)).round();
    final totalSteps = numLoops * numSteps;

    // Determine output length: last trigger end + longest tail.
    int outputFrames = totalSteps * stepFrames;
    for (int t = 0; t < numTracks; t++) {
      final wav = trackData[t];
      if (wav == null) continue;
      final trimStartF = _msToFrames(trimStarts[t].inMilliseconds, wav.sampleRate);
      final trimEndF = trimEnds[t] != null
          ? _msToFrames(trimEnds[t]!.inMilliseconds, wav.sampleRate).clamp(0, wav.numFrames)
          : wav.numFrames;
      final sampleLen = (trimEndF - trimStartF).clamp(0, wav.numFrames);
      for (int step = totalSteps - 1; step >= 0; step--) {
        if (steps[t][step % numSteps]) {
          final tail = step * stepFrames + sampleLen;
          if (tail > outputFrames) outputFrames = tail;
          break;
        }
      }
    }

    // ── Mix into a float buffer ─────────────────────────────────────────────
    final buf = Float64List(outputFrames * _kNumChannels);

    int doneSteps = 0;
    final totalWork = numTracks * totalSteps;

    for (int t = 0; t < numTracks; t++) {
      final wav = trackData[t];
      if (wav == null) {
        doneSteps += totalSteps;
        onProgress?.call(doneSteps / totalWork);
        continue;
      }

      final vol = volumes[t];
      final mono = wav.numChannels == 1;
      final trimStartF = _msToFrames(trimStarts[t].inMilliseconds, wav.sampleRate);
      final trimEndF = trimEnds[t] != null
          ? _msToFrames(trimEnds[t]!.inMilliseconds, wav.sampleRate).clamp(0, wav.numFrames)
          : wav.numFrames;

      for (int step = 0; step < totalSteps; step++) {
        if (steps[t][step % numSteps]) {
          final offset = step * stepFrames;
          for (int frame = trimStartF; frame < trimEndF; frame++) {
            final outFrame = offset + (frame - trimStartF);
            if (outFrame >= outputFrames) break;

            double l, r;
            if (mono) {
              l = r = wav.samples[frame] / 32768.0 * vol;
            } else {
              l = wav.samples[frame * 2] / 32768.0 * vol;
              r = wav.samples[frame * 2 + 1] / 32768.0 * vol;
            }
            buf[outFrame * 2] += l;
            buf[outFrame * 2 + 1] += r;
          }
        }
        doneSteps++;
        if (doneSteps % 16 == 0) {
          onProgress?.call(doneSteps / totalWork * 0.95);
        }
      }
    }

    // ── Normalise & write WAV in chunks ────────────────────────────────────
    double peak = 0;
    for (final v in buf) {
      if (v.abs() > peak) peak = v.abs();
    }
    final scale = peak > 1.0 ? 1.0 / peak : 1.0;

    // Stream PCM conversion in chunks instead of holding a second full-size
    // Int16List buffer.  This halves peak RSS for long exports.
    await writeWavChunked(
      outputPath: outputPath,
      mixBuffer: buf,
      scale: scale,
      sampleRate: _kSampleRate,
      numChannels: _kNumChannels,
    );
    onProgress?.call(1.0);
  }

  static int _msToFrames(int ms, int sampleRate) =>
      (ms * sampleRate / 1000).round();

}
