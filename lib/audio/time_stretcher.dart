import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';
import 'wav_io.dart';

// ---------------------------------------------------------------------------
// Phase-vocoder time stretcher
// ---------------------------------------------------------------------------

/// Fixed analysis hop size (samples). Kept constant across all FFT sizes so
/// that the time-domain resolution of the analyser does not change with ratio.
const int kStretchHopA = 512;

/// Returns the smallest power-of-2 FFT size such that the synthesis hop
/// (hopA × ratio) does not exceed the frame size — which would leave
/// uncovered gaps in the overlap-add output.
int _fftSizeForRatio(double ratio) {
  int n = 2048;
  while (n < kStretchHopA * ratio) n <<= 1;
  return n;
}

/// Wraps [p] into (−π, π].
double _wrapPhase(double p) {
  const twoPi = 2 * math.pi;
  return p - twoPi * (p / twoPi + 0.5).floorToDouble();
}

/// Phase-vocoder time stretch of [mono] by [ratio].
///
/// ratio > 1.0 → output is longer (slower)
/// ratio < 1.0 → output is shorter (faster)
///
/// Input and output are normalised floating-point samples in [−1.0, 1.0].
/// The returned list has exactly `(mono.length × ratio).round()` samples
/// (or fewer if the computed output is shorter due to extreme ratios).
Float64List timeStretch(Float64List mono, double ratio) {
  if (mono.isEmpty || ratio <= 0) return Float64List(0);

  final fftSize = _fftSizeForRatio(ratio);
  final hopS = (kStretchHopA * ratio).round().clamp(1, fftSize);
  final numBins = fftSize ~/ 2 + 1;

  // Hann window.
  final window = Float64List(fftSize);
  for (int i = 0; i < fftSize; i++) {
    window[i] = 0.5 * (1.0 - math.cos(2 * math.pi * i / (fftSize - 1)));
  }

  // Zero-pad input: half a frame prepended so the first window is centred over
  // sample 0, and a full frame appended so the last window covers the tail.
  final padLen = fftSize ~/ 2;
  final padded = Float64List(padLen + mono.length + fftSize);
  padded.setRange(padLen, padLen + mono.length, mono);

  final numFrames = (padded.length - fftSize) ~/ kStretchHopA + 1;
  final outputLen = numFrames * hopS + fftSize;
  final output = Float64List(outputLen);
  final norm = Float64List(outputLen);

  final prevPhase = Float64List(numBins);
  final synthPhase = Float64List(numBins);
  bool firstFrame = true;

  final re = Float64List(fftSize);
  final im = Float64List(fftSize);
  const twoPi = 2 * math.pi;

  int outputPos = 0;
  for (int frameStart = 0;
      frameStart + fftSize <= padded.length;
      frameStart += kStretchHopA) {
    // Extract windowed analysis frame.
    for (int i = 0; i < fftSize; i++) {
      re[i] = padded[frameStart + i] * window[i];
      im[i] = 0.0;
    }
    fft(re, im);

    // Phase processing — positive frequencies only.
    for (int k = 0; k < numBins; k++) {
      final mag = math.sqrt(re[k] * re[k] + im[k] * im[k]);
      final phase = math.atan2(im[k], re[k]);

      if (firstFrame) {
        // Seed synthesis phase directly from analysis so the first output
        // frame has correct phase (no delta to compute yet).
        synthPhase[k] = phase;
      } else {
        final expectedAdv = twoPi * k * kStretchHopA / fftSize;
        final instFreq =
            twoPi * k / fftSize + _wrapPhase(phase - prevPhase[k] - expectedAdv) / kStretchHopA;
        synthPhase[k] += instFreq * hopS;
      }
      prevPhase[k] = phase;

      re[k] = mag * math.cos(synthPhase[k]);
      im[k] = mag * math.sin(synthPhase[k]);
    }
    // Mirror conjugate symmetry so IFFT produces a real-valued signal.
    for (int k = 1; k < fftSize ~/ 2; k++) {
      re[fftSize - k] = re[k];
      im[fftSize - k] = -im[k];
    }
    firstFrame = false;

    ifft(re, im);

    // Weighted overlap-add.
    for (int i = 0; i < fftSize; i++) {
      final pos = outputPos + i;
      if (pos < outputLen) {
        output[pos] += re[i] * window[i];
        norm[pos] += window[i] * window[i];
      }
    }
    outputPos += hopS;
  }

  // Normalise by accumulated window power.
  for (int i = 0; i < outputLen; i++) {
    if (norm[i] > 1e-8) output[i] /= norm[i];
  }

  // Trim to expected length.  The first `leadSynthSamples` of the output
  // correspond to the leading zero-padding and are discarded.
  final leadSynthSamples =
      ((padLen / kStretchHopA).floor() * hopS).clamp(0, outputLen);
  final expectedLen = (mono.length * ratio).round();
  final start = leadSynthSamples;
  final end = (start + expectedLen).clamp(0, outputLen);
  return Float64List.sublistView(output, start, end);
}

// ---------------------------------------------------------------------------
// File-level entry point for Flutter's compute() isolate
// ---------------------------------------------------------------------------

/// Arguments for [stretchWavFile]. Must be sendable across isolate boundaries
/// (all fields are primitives).
class StretchArgs {
  const StretchArgs({
    required this.inputPath,
    required this.ratio,
    required this.outputPath,
  });
  final String inputPath;
  final double ratio;
  final String outputPath;
}

/// Read [args.inputPath], time-stretch by [args.ratio], write to
/// [args.outputPath]. Returns the output path on success, null on failure.
///
/// Top-level so it can be passed directly to Flutter's [compute] function.
Future<String?> stretchWavFile(StretchArgs args) async {
  final wav = await readWav(args.inputPath);
  if (wav == null || wav.numFrames == 0) return null;

  // Stretch each channel independently to preserve stereo imaging.
  final channels = List.generate(wav.numChannels, (ch) {
    final data = Float64List(wav.numFrames);
    for (int f = 0; f < wav.numFrames; f++) {
      data[f] = wav.samples[f * wav.numChannels + ch] / 32767.0;
    }
    return timeStretch(data, args.ratio);
  });

  final outputFrames = channels[0].length;
  if (outputFrames == 0) return null;

  // Interleave channels into a mix buffer.
  final mixBuffer = Float64List(outputFrames * wav.numChannels);
  for (int f = 0; f < outputFrames; f++) {
    for (int ch = 0; ch < wav.numChannels; ch++) {
      mixBuffer[f * wav.numChannels + ch] = channels[ch][f];
    }
  }

  // Only scale down to prevent clipping — never boost a quiet signal.
  // The previous threshold (1e-10) normalised everything to 0.98× peak,
  // changing the level of quiet recordings relative to the original.
  double peak = 0.0;
  for (final s in mixBuffer) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  final scale = peak > 1.0 ? 0.98 / peak : 1.0;

  await writeWavChunked(
    outputPath: args.outputPath,
    mixBuffer: mixBuffer,
    scale: scale,
    sampleRate: wav.sampleRate,
    numChannels: wav.numChannels,
  );

  return args.outputPath;
}
