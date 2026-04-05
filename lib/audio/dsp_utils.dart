import 'dart:math' as math;
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// PCM WAV generation helpers
// ---------------------------------------------------------------------------

/// Number of samples over which a linear fade-in and fade-out are applied by
/// [buildWav]. At 44 100 Hz this is ~5.8 ms — short enough to be inaudible as
/// an effect yet long enough to prevent click/pop artefacts caused by an
/// abrupt amplitude step at the very start or end of a synthesised sample.
const int kWavFadeSamples = 256;

/// Builds a 16-bit mono PCM WAV file in memory.
///
/// A linear fade-in is applied to the first [kWavFadeSamples] samples and a
/// linear fade-out to the last [kWavFadeSamples] samples. This eliminates
/// click artefacts that occur when noise-based generators (snare, hi-hats)
/// produce a non-zero first sample, or when a sample is abruptly cut off at
/// its natural end.
Uint8List buildWav(Float64List samples, int sampleRate) {
  final numSamples = samples.length;
  final dataBytes = numSamples * 2;
  final totalBytes = 44 + dataBytes;
  final fadeSamples = kWavFadeSamples.clamp(0, numSamples ~/ 2);

  final buf = ByteData(totalBytes);
  int pos = 0;

  buf.setUint8(pos++, 0x52); // R
  buf.setUint8(pos++, 0x49); // I
  buf.setUint8(pos++, 0x46); // F
  buf.setUint8(pos++, 0x46); // F
  buf.setUint32(pos, totalBytes - 8, Endian.little); pos += 4;
  buf.setUint8(pos++, 0x57); // W
  buf.setUint8(pos++, 0x41); // A
  buf.setUint8(pos++, 0x56); // V
  buf.setUint8(pos++, 0x45); // E

  buf.setUint8(pos++, 0x66); // f
  buf.setUint8(pos++, 0x6D); // m
  buf.setUint8(pos++, 0x74); // t
  buf.setUint8(pos++, 0x20); // (space)
  buf.setUint32(pos, 16, Endian.little); pos += 4;
  buf.setUint16(pos, 1, Endian.little); pos += 2;  // PCM
  buf.setUint16(pos, 1, Endian.little); pos += 2;  // mono
  buf.setUint32(pos, sampleRate, Endian.little); pos += 4;
  buf.setUint32(pos, sampleRate * 2, Endian.little); pos += 4;
  buf.setUint16(pos, 2, Endian.little); pos += 2;
  buf.setUint16(pos, 16, Endian.little); pos += 2;

  buf.setUint8(pos++, 0x64); // d
  buf.setUint8(pos++, 0x61); // a
  buf.setUint8(pos++, 0x74); // t
  buf.setUint8(pos++, 0x61); // a
  buf.setUint32(pos, dataBytes, Endian.little); pos += 4;

  for (int i = 0; i < numSamples; i++) {
    double s = samples[i];
    if (fadeSamples > 0) {
      if (i < fadeSamples) s *= i / fadeSamples;
      if (i >= numSamples - fadeSamples) s *= (numSamples - 1 - i) / fadeSamples;
    }
    final v = (s * 32767).clamp(-32768, 32767).toInt();
    buf.setInt16(pos, v, Endian.little);
    pos += 2;
  }

  return buf.buffer.asUint8List();
}

/// Exponential amplitude envelope.
double dspEnv(int i, int totalSamples, double decayRate) =>
    math.exp(-decayRate * i / totalSamples);

// ---------------------------------------------------------------------------
// Synthesised drum generators
// ---------------------------------------------------------------------------

// Deterministic seeds for noise-based drum generators.
// Each value was chosen to produce a natural-sounding stochastic texture for
// the respective instrument; changing a seed would alter the timbre.
const int _kSnareNoiseSeed = 42;
const int _kRimShotNoiseSeed = 99;
const int _kHiHatClosedNoiseSeed = 7;
const int _kHiHatOpenNoiseSeed = 13;
const int _kClapNoiseSeed = 55;

Float64List generateKick808(int sr) {
  const durationMs = 500;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  const f0 = 180.0, f1 = 40.0;
  final sweepSamples = sr * 200 ~/ 1000;
  double phase = 0.0;
  for (int i = 0; i < n; i++) {
    final frac = (i < sweepSamples) ? i / sweepSamples : 1.0;
    final freq = f0 + (f1 - f0) * frac;
    phase += 2 * math.pi * freq / sr;
    buf[i] = math.sin(phase) * dspEnv(i, n, 4.0) * 0.72;
  }
  return buf;
}

Float64List generateKickHard(int sr) {
  const durationMs = 300;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  const f0 = 240.0, f1 = 50.0;
  final sweepSamples = sr * 60 ~/ 1000;
  double phase = 0.0;
  for (int i = 0; i < n; i++) {
    final frac = (i < sweepSamples) ? i / sweepSamples : 1.0;
    final freq = f0 + (f1 - f0) * frac;
    phase += 2 * math.pi * freq / sr;
    buf[i] = math.sin(phase) * dspEnv(i, n, 8.0) * 0.9;
  }
  return buf;
}

Float64List generateSnare(int sr) {
  const durationMs = 200;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  final rng = math.Random(_kSnareNoiseSeed);
  double phase = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = dspEnv(i, n, 8.0);
    phase += 2 * math.pi * 200.0 / sr;
    buf[i] = ((rng.nextDouble() * 2 - 1) * 0.6 + math.sin(phase) * 0.4) * amp * 0.85;
  }
  return buf;
}

Float64List generateRimShot(int sr) {
  const durationMs = 120;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  final rng = math.Random(_kRimShotNoiseSeed);
  double phase = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = dspEnv(i, n, 15.0);
    phase += 2 * math.pi * 800.0 / sr;
    buf[i] = (math.sin(phase) * 0.7 + (rng.nextDouble() * 2 - 1) * 0.3) * amp * 0.8;
  }
  return buf;
}

Float64List generateHiHatClosed(int sr) {
  const durationMs = 80;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  final rng = math.Random(_kHiHatClosedNoiseSeed);
  double prev = 0.0;
  double lastNoise = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = dspEnv(i, n, 12.0);
    final noise = rng.nextDouble() * 2 - 1;
    final hp = 0.95 * (prev + noise - lastNoise);
    prev = hp;
    lastNoise = noise;
    buf[i] = hp * amp * 0.7;
  }
  return buf;
}

Float64List generateHiHatOpen(int sr) {
  const durationMs = 600;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  final rng = math.Random(_kHiHatOpenNoiseSeed);
  double prev = 0.0;
  double lastNoise = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = dspEnv(i, n, 3.5);
    final noise = rng.nextDouble() * 2 - 1;
    final hp = 0.95 * (prev + noise - lastNoise);
    prev = hp;
    lastNoise = noise;
    buf[i] = hp * amp * 0.65;
  }
  return buf;
}

Float64List generateClap(int sr) {
  const durationMs = 220;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  final rng = math.Random(_kClapNoiseSeed);
  for (int burst = 0; burst < 3; burst++) {
    final offset = sr * burst * 10 ~/ 1000;
    final burstLen = sr * 14 ~/ 1000;
    for (int i = 0; i < burstLen && offset + i < n; i++) {
      buf[offset + i] += (rng.nextDouble() * 2 - 1) * dspEnv(i, burstLen, 14.0) * 0.85;
    }
  }
  final tailStart = sr * 30 ~/ 1000;
  for (int i = tailStart; i < n; i++) {
    buf[i] += (rng.nextDouble() * 2 - 1) * dspEnv(i - tailStart, n - tailStart, 10.0) * 0.45;
  }
  return buf;
}

Float64List generateTom(int sr) {
  const durationMs = 400;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  const f0 = 120.0, f1 = 60.0;
  final sweepSamples = sr * 150 ~/ 1000;
  double phase = 0.0;
  for (int i = 0; i < n; i++) {
    final frac = (i < sweepSamples) ? i / sweepSamples : 1.0;
    final freq = f0 + (f1 - f0) * frac;
    phase += 2 * math.pi * freq / sr;
    buf[i] = math.sin(phase) * dspEnv(i, n, 5.0) * 0.85;
  }
  return buf;
}

Float64List generateCowbell(int sr) {
  const durationMs = 800;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  double p1 = 0.0, p2 = 0.0;
  for (int i = 0; i < n; i++) {
    p1 += 2 * math.pi * 562.0 / sr;
    p2 += 2 * math.pi * 845.0 / sr;
    final amp = dspEnv(i, n, 6.0);
    final s1 = math.sin(p1) > 0 ? 1.0 : -1.0;
    final s2 = math.sin(p2) > 0 ? 1.0 : -1.0;
    buf[i] = (s1 + s2) * 0.5 * amp * 0.6;
  }
  return buf;
}
