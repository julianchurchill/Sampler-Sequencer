import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// ---------------------------------------------------------------------------
// PCM WAV generation helpers
// ---------------------------------------------------------------------------

/// Builds a 16-bit mono PCM WAV file in memory.
Uint8List _buildWav(Float64List samples, int sampleRate) {
  final numSamples = samples.length;
  final dataBytes = numSamples * 2; // 16-bit = 2 bytes per sample
  final totalBytes = 44 + dataBytes;

  final buf = ByteData(totalBytes);
  int pos = 0;

  // RIFF header
  buf.setUint8(pos++, 0x52); // R
  buf.setUint8(pos++, 0x49); // I
  buf.setUint8(pos++, 0x46); // F
  buf.setUint8(pos++, 0x46); // F
  buf.setUint32(pos, totalBytes - 8, Endian.little); pos += 4;
  buf.setUint8(pos++, 0x57); // W
  buf.setUint8(pos++, 0x41); // A
  buf.setUint8(pos++, 0x56); // V
  buf.setUint8(pos++, 0x45); // E

  // fmt chunk
  buf.setUint8(pos++, 0x66); // f
  buf.setUint8(pos++, 0x6D); // m
  buf.setUint8(pos++, 0x74); // t
  buf.setUint8(pos++, 0x20); // (space)
  buf.setUint32(pos, 16, Endian.little); pos += 4; // chunk size
  buf.setUint16(pos, 1, Endian.little); pos += 2;  // PCM
  buf.setUint16(pos, 1, Endian.little); pos += 2;  // mono
  buf.setUint32(pos, sampleRate, Endian.little); pos += 4;
  buf.setUint32(pos, sampleRate * 2, Endian.little); pos += 4; // byte rate
  buf.setUint16(pos, 2, Endian.little); pos += 2;  // block align
  buf.setUint16(pos, 16, Endian.little); pos += 2; // bits per sample

  // data chunk
  buf.setUint8(pos++, 0x64); // d
  buf.setUint8(pos++, 0x61); // a
  buf.setUint8(pos++, 0x74); // t
  buf.setUint8(pos++, 0x61); // a
  buf.setUint32(pos, dataBytes, Endian.little); pos += 4;

  for (int i = 0; i < numSamples; i++) {
    final v = (samples[i] * 32767).clamp(-32768, 32767).toInt();
    buf.setInt16(pos, v, Endian.little);
    pos += 2;
  }

  return buf.buffer.asUint8List();
}

/// Exponential amplitude envelope (fast attack, exponential decay).
double _env(int i, int totalSamples, double decayRate) {
  return math.exp(-decayRate * i / totalSamples);
}

// ---- Synthesised drum sounds ------------------------------------------------

Float64List _generateKick(int sr) {
  const durationMs = 500;
  final n = (sr * durationMs ~/ 1000);
  final buf = Float64List(n);
  // Sine with frequency sweep: 180 Hz → 40 Hz over 200 ms
  const f0 = 180.0;
  const f1 = 40.0;
  final sweepSamples = sr * 200 ~/ 1000;
  double phase = 0.0;
  for (int i = 0; i < n; i++) {
    final t = i / sr;
    final frac = (i < sweepSamples) ? (i / sweepSamples) : 1.0;
    final freq = f0 + (f1 - f0) * frac;
    phase += 2 * math.pi * freq / sr;
    final amp = _env(i, n, 4.0);
    buf[i] = math.sin(phase) * amp * 0.9;
  }
  return buf;
}

Float64List _generateSnare(int sr) {
  const durationMs = 200;
  final n = (sr * durationMs ~/ 1000);
  final buf = Float64List(n);
  final rng = math.Random(42);
  // Body: 200 Hz sine + white noise
  double phase = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = _env(i, n, 8.0);
    final noise = (rng.nextDouble() * 2 - 1);
    phase += 2 * math.pi * 200.0 / sr;
    buf[i] = (noise * 0.6 + math.sin(phase) * 0.4) * amp * 0.85;
  }
  return buf;
}

Float64List _generateHiHatClosed(int sr) {
  const durationMs = 80;
  final n = (sr * durationMs ~/ 1000);
  final buf = Float64List(n);
  final rng = math.Random(7);
  // High-passed white noise: simple HPF via difference
  double prev = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = _env(i, n, 12.0);
    final noise = (rng.nextDouble() * 2 - 1);
    // 1-pole HPF: y[n] = 0.9*(y[n-1] + x[n] - x[n-1])
    final hp = 0.95 * (prev + noise - (i > 0 ? (rng.nextDouble() * 2 - 1) : 0));
    prev = hp;
    buf[i] = hp * amp * 0.7;
  }
  return buf;
}

Float64List _generateHiHatOpen(int sr) {
  const durationMs = 600;
  final n = (sr * durationMs ~/ 1000);
  final buf = Float64List(n);
  final rng = math.Random(13);
  double prev = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = _env(i, n, 3.5);
    final noise = (rng.nextDouble() * 2 - 1);
    final hp = 0.95 * (prev + noise - (i > 0 ? (rng.nextDouble() * 2 - 1) : 0));
    prev = hp;
    buf[i] = hp * amp * 0.65;
  }
  return buf;
}

// ---------------------------------------------------------------------------
// AudioEngine
// ---------------------------------------------------------------------------

const int _kSampleRate = 44100;

typedef _SampleGenerator = Float64List Function(int sr);

final List<_SampleGenerator> _generators = [
  _generateKick,
  _generateSnare,
  _generateHiHatClosed,
  _generateHiHatOpen,
];

class AudioEngine {
  final List<AudioPlayer> _players = [];
  final List<String?> _customPaths = List.filled(4, null);
  final List<String> _defaultWavPaths = [];
  bool _ready = false;

  bool get isReady => _ready;

  Future<void> init() async {
    final tmpDir = await getTemporaryDirectory();

    // Write default synth WAVs to temp directory.
    for (int i = 0; i < 4; i++) {
      final wavData = _buildWav(_generators[i](_kSampleRate), _kSampleRate);
      final path = '${tmpDir.path}/drum_default_$i.wav';
      await File(path).writeAsBytes(wavData);
      _defaultWavPaths.add(path);
    }

    // One AudioPlayer per track (low-latency mode).
    for (int i = 0; i < 4; i++) {
      final player = AudioPlayer();
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setReleaseMode(ReleaseMode.stop);
      _players.add(player);
    }

    _ready = true;
  }

  /// Set a custom audio file path for a track (null = use synth default).
  void setCustomPath(int track, String? path) {
    _customPaths[track] = path;
  }

  String? customPath(int track) => _customPaths[track];

  /// Trigger a one-shot hit on [track].
  Future<void> trigger(int track) async {
    if (!_ready) return;
    final path = _customPaths[track] ?? _defaultWavPaths[track];
    try {
      await _players[track].stop();
      await _players[track].play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('AudioEngine trigger error: $e');
    }
  }

  Future<void> dispose() async {
    for (final p in _players) {
      await p.dispose();
    }
    _players.clear();
  }
}
