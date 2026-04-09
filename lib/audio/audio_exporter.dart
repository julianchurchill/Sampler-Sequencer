import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../constants.dart';
import 'wav_io.dart';

const int _kSampleRate = 44100;
const int _kNumChannels = 2; // stereo output
const double _kStepsPerQuarterNote = 4.0;

/// Parameters passed to the background export isolate via [compute].
class _ExportParams {
  const _ExportParams({
    required this.samplePaths,
    required this.volumes,
    required this.trimStarts,
    required this.trimEnds,
    required this.steps,
    required this.bpm,
    required this.numLoops,
    required this.outputPath,
  });

  final List<String> samplePaths;
  final List<double> volumes;
  final List<Duration> trimStarts;
  final List<Duration?> trimEnds;
  final List<List<bool>> steps;
  final int bpm;
  final int numLoops;
  final String outputPath;
}

/// Offline renderer: reads each track's WAV file, mixes them at the correct
/// step-sequence timing, and writes a stereo 44100 Hz 16-bit WAV.
///
/// The heavy CPU work (mixing loop + normalisation) runs on a background
/// isolate via [compute] so the Flutter UI thread is never blocked.
class AudioExporter {
  /// Mix and export [numLoops] passes of the sequence to a 16-bit stereo WAV
  /// at [outputPath].  Runs on a background isolate.
  ///
  /// Returns the list of track indices whose samples could not be decoded
  /// (non-WAV files) and were silenced in the mix.
  ///
  /// Throws [ArgumentError] if [outputPath] contains `..` (path traversal) or
  /// does not end with `.wav`.
  static Future<List<int>> export({
    required List<String> samplePaths,
    required List<double> volumes,
    required List<Duration> trimStarts,
    required List<Duration?> trimEnds,
    required List<List<bool>> steps,
    required int bpm,
    required int numLoops,
    required String outputPath,
  }) {
    // Guard against path traversal and incorrect file types.  The canonical
    // caller (ExportSheet) always passes a path inside getTemporaryDirectory(),
    // but this check defends against future misuse of the API.
    if (outputPath.contains('..')) {
      throw ArgumentError.value(
        outputPath, 'outputPath',
        'must not contain path traversal components (..)',
      );
    }
    if (!outputPath.toLowerCase().endsWith('.wav')) {
      throw ArgumentError.value(
        outputPath, 'outputPath',
        'must have a .wav extension — export() only writes WAV data',
      );
    }

    return compute(_runExport, _ExportParams(
      samplePaths: samplePaths,
      volumes: volumes,
      trimStarts: trimStarts,
      trimEnds: trimEnds,
      steps: steps,
      bpm: bpm,
      numLoops: numLoops,
      outputPath: outputPath,
    ));
  }
}

int _msToFrames(int ms, int sampleRate) => (ms * sampleRate / 1000).round();

/// Top-level function required by [compute] — must not be a closure.
Future<List<int>> _runExport(_ExportParams p) async {
  final unsupportedTracks = <int>[];

  // ── Load WAV data for every track ───────────────────────────────────────
  final trackData = List<WavData?>.filled(kNumTracks, null);
  for (int t = 0; t < kNumTracks; t++) {
    final wav = await readWav(p.samplePaths[t]);
    if (wav == null) {
      unsupportedTracks.add(t);
    } else {
      trackData[t] = wav;
    }
  }

  // ── Compute timeline ────────────────────────────────────────────────────
  final stepFrames = (_kSampleRate * 60.0 / (p.bpm * _kStepsPerQuarterNote)).round();
  final totalSteps = p.numLoops * kNumSteps;

  // Determine output length: last trigger end + longest tail.
  int outputFrames = totalSteps * stepFrames;
  for (int t = 0; t < kNumTracks; t++) {
    final wav = trackData[t];
    if (wav == null) continue;
    final trimStartF = _msToFrames(p.trimStarts[t].inMilliseconds, wav.sampleRate);
    final trimEndF = p.trimEnds[t] != null
        ? _msToFrames(p.trimEnds[t]!.inMilliseconds, wav.sampleRate).clamp(0, wav.numFrames)
        : wav.numFrames;
    final sampleLen = (trimEndF - trimStartF).clamp(0, wav.numFrames);
    for (int step = totalSteps - 1; step >= 0; step--) {
      if (p.steps[t][step % kNumSteps]) {
        final tail = step * stepFrames + sampleLen;
        if (tail > outputFrames) outputFrames = tail;
        break;
      }
    }
  }

  // ── Mix into a float buffer ─────────────────────────────────────────────
  final buf = Float64List(outputFrames * _kNumChannels);

  for (int t = 0; t < kNumTracks; t++) {
    final wav = trackData[t];
    if (wav == null) continue;

    final vol = p.volumes[t];
    final mono = wav.numChannels == 1;
    final trimStartF = _msToFrames(p.trimStarts[t].inMilliseconds, wav.sampleRate);
    final trimEndF = p.trimEnds[t] != null
        ? _msToFrames(p.trimEnds[t]!.inMilliseconds, wav.sampleRate).clamp(0, wav.numFrames)
        : wav.numFrames;

    for (int step = 0; step < totalSteps; step++) {
      if (p.steps[t][step % kNumSteps]) {
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
    outputPath: p.outputPath,
    mixBuffer: buf,
    scale: scale,
    sampleRate: _kSampleRate,
    numChannels: _kNumChannels,
  );

  return unsupportedTracks;
}
