import 'dart:typed_data';

import '../constants.dart';
import 'wav_io.dart';

/// Offline renderer: reads each track's WAV file, mixes them at the correct
/// step-sequence timing, and writes a stereo 44100 Hz 16-bit WAV.
class AudioExporter {
  static const int _kSampleRate = 44100;
  static const int _kNumChannels = 2; // stereo output
  static const double _kStepsPerQuarterNote = 4.0;

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

    const numTracks = kNumTracks;
    const numSteps = kNumSteps;

    // ── Load WAV data for every track ───────────────────────────────────────
    final trackData = List<WavData?>.filled(numTracks, null);
    for (int t = 0; t < numTracks; t++) {
      final wav = await readWav(samplePaths[t]);
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
