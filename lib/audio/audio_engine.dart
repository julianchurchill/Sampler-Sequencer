import 'dart:async';
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
  final dataBytes = numSamples * 2;
  final totalBytes = 44 + dataBytes;

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
    final v = (samples[i] * 32767).clamp(-32768, 32767).toInt();
    buf.setInt16(pos, v, Endian.little);
    pos += 2;
  }

  return buf.buffer.asUint8List();
}

/// Exponential amplitude envelope.
double _env(int i, int totalSamples, double decayRate) =>
    math.exp(-decayRate * i / totalSamples);

// ---------------------------------------------------------------------------
// Synthesised drum generators
// ---------------------------------------------------------------------------

Float64List _generateKick808(int sr) {
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
    buf[i] = math.sin(phase) * _env(i, n, 4.0) * 0.9;
  }
  return buf;
}

Float64List _generateKickHard(int sr) {
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
    buf[i] = math.sin(phase) * _env(i, n, 8.0) * 0.9;
  }
  return buf;
}

Float64List _generateSnare(int sr) {
  const durationMs = 200;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  final rng = math.Random(42);
  double phase = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = _env(i, n, 8.0);
    phase += 2 * math.pi * 200.0 / sr;
    buf[i] = ((rng.nextDouble() * 2 - 1) * 0.6 + math.sin(phase) * 0.4) * amp * 0.85;
  }
  return buf;
}

Float64List _generateRimShot(int sr) {
  const durationMs = 120;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  final rng = math.Random(99);
  double phase = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = _env(i, n, 15.0);
    phase += 2 * math.pi * 800.0 / sr;
    buf[i] = (math.sin(phase) * 0.7 + (rng.nextDouble() * 2 - 1) * 0.3) * amp * 0.8;
  }
  return buf;
}

Float64List _generateHiHatClosed(int sr) {
  const durationMs = 80;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  final rng = math.Random(7);
  double prev = 0.0;
  double lastNoise = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = _env(i, n, 12.0);
    final noise = rng.nextDouble() * 2 - 1;
    final hp = 0.95 * (prev + noise - lastNoise);
    prev = hp;
    lastNoise = noise;
    buf[i] = hp * amp * 0.7;
  }
  return buf;
}

Float64List _generateHiHatOpen(int sr) {
  const durationMs = 600;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  final rng = math.Random(13);
  double prev = 0.0;
  double lastNoise = 0.0;
  for (int i = 0; i < n; i++) {
    final amp = _env(i, n, 3.5);
    final noise = rng.nextDouble() * 2 - 1;
    final hp = 0.95 * (prev + noise - lastNoise);
    prev = hp;
    lastNoise = noise;
    buf[i] = hp * amp * 0.65;
  }
  return buf;
}

Float64List _generateClap(int sr) {
  const durationMs = 220;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  final rng = math.Random(55);
  // Three short noise bursts 10 ms apart
  for (int burst = 0; burst < 3; burst++) {
    final offset = sr * burst * 10 ~/ 1000;
    final burstLen = sr * 14 ~/ 1000;
    for (int i = 0; i < burstLen && offset + i < n; i++) {
      buf[offset + i] += (rng.nextDouble() * 2 - 1) * _env(i, burstLen, 14.0) * 0.85;
    }
  }
  // Noise tail
  final tailStart = sr * 30 ~/ 1000;
  for (int i = tailStart; i < n; i++) {
    buf[i] += (rng.nextDouble() * 2 - 1) * _env(i - tailStart, n - tailStart, 10.0) * 0.45;
  }
  return buf;
}

Float64List _generateTom(int sr) {
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
    buf[i] = math.sin(phase) * _env(i, n, 5.0) * 0.85;
  }
  return buf;
}

Float64List _generateCowbell(int sr) {
  const durationMs = 800;
  final n = sr * durationMs ~/ 1000;
  final buf = Float64List(n);
  double p1 = 0.0, p2 = 0.0;
  for (int i = 0; i < n; i++) {
    p1 += 2 * math.pi * 562.0 / sr;
    p2 += 2 * math.pi * 845.0 / sr;
    final amp = _env(i, n, 6.0);
    final s1 = math.sin(p1) > 0 ? 1.0 : -1.0;
    final s2 = math.sin(p2) > 0 ? 1.0 : -1.0;
    buf[i] = (s1 + s2) * 0.5 * amp * 0.6;
  }
  return buf;
}

// ---------------------------------------------------------------------------
// Preset catalogue
// ---------------------------------------------------------------------------

typedef _SampleGenerator = Float64List Function(int sr);

class DrumPreset {
  const DrumPreset(this.name, this.generator);
  final String name;
  final _SampleGenerator generator;
}

final List<DrumPreset> kDrumPresets = [
  DrumPreset('Kick 808',  _generateKick808),
  DrumPreset('Kick Hard', _generateKickHard),
  DrumPreset('Snare',     _generateSnare),
  DrumPreset('Rim Shot',  _generateRimShot),
  DrumPreset('HH Closed', _generateHiHatClosed),
  DrumPreset('HH Open',   _generateHiHatOpen),
  DrumPreset('Clap',      _generateClap),
  DrumPreset('Tom',       _generateTom),
  DrumPreset('Cowbell',   _generateCowbell),
];

/// Default preset index assigned to each track (0=Kick808, 2=Snare, 4=HH Closed, 5=HH Open).
const List<int> kDefaultPresetIndices = [0, 2, 4, 5];

// ---------------------------------------------------------------------------
// AudioEngine
// ---------------------------------------------------------------------------

const int _kSampleRate = 44100;

class AudioEngine {
  final List<AudioPlayer> _players = [];

  /// One cached WAV path per preset, indexed by kDrumPresets index.
  final List<String> _presetPaths = [];

  /// Per-track active preset index.
  final List<int> _trackPresetIndex = List.from(kDefaultPresetIndices);

  /// Per-track custom file override (null = use preset).
  final List<String?> _trackCustomPath = List.filled(4, null);

  /// Per-track volume (0.0–1.0, default 1.0).
  final List<double> _trackVolume = List.filled(4, 1.0);

  /// Per-track trim start (default Duration.zero).
  final List<Duration> _trimStart = List.filled(4, Duration.zero);

  /// Per-track trim end (null = play to end of sample).
  final List<Duration?> _trimEnd = List.filled(4, null);

  /// Timers used to stop playback at trim end.
  final List<Timer?> _trimTimers = List.filled(4, null);

  /// Per-track display name shown in the UI.
  final List<String> _trackNames = [
    kDrumPresets[kDefaultPresetIndices[0]].name,
    kDrumPresets[kDefaultPresetIndices[1]].name,
    kDrumPresets[kDefaultPresetIndices[2]].name,
    kDrumPresets[kDefaultPresetIndices[3]].name,
  ];

  bool _ready = false;

  /// Monotonically increasing counter per track. When a new trigger arrives
  /// while a previous stop()→play() is in flight, the stale play() is skipped.
  final List<int> _triggerGen = List.filled(4, 0);

  bool get isReady => _ready;

  String trackName(int track) => _trackNames[track];
  bool hasCustomPath(int track) => _trackCustomPath[track] != null;
  String? customPath(int track) => _trackCustomPath[track];
  int presetIndex(int track) => _trackPresetIndex[track];
  double trackVolume(int track) => _trackVolume[track];
  Duration trimStart(int track) => _trimStart[track];
  Duration? trimEnd(int track) => _trimEnd[track];
  bool hasTrim(int track) =>
      _trimStart[track] != Duration.zero || _trimEnd[track] != null;

  Future<void> setTrackVolume(int track, double volume) async {
    _trackVolume[track] = volume.clamp(0.0, 1.0);
    await _players[track].setVolume(_trackVolume[track]);
  }

  Future<void> init() async {
    final tmpDir = await getTemporaryDirectory();

    // Synthesise all presets to temp WAV files.
    for (int i = 0; i < kDrumPresets.length; i++) {
      final wavData = _buildWav(kDrumPresets[i].generator(_kSampleRate), _kSampleRate);
      final path = '${tmpDir.path}/preset_$i.wav';
      await File(path).writeAsBytes(wavData);
      _presetPaths.add(path);
    }

    // One MediaPlayer AudioPlayer per track.
    // MediaPlayer (mediaPlayer mode) supports seek(), which is required for
    // non-destructive trim playback. AudioFocus.none prevents each player
    // requesting AUDIOFOCUS_GAIN, which would cause Android to notify other
    // in-app players to stop — all 4 tracks play independently.
    for (int i = 0; i < 4; i++) {
      final player = AudioPlayer();
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setAudioContext(AudioContext(
        android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      ));
      _players.add(player);
    }

    _ready = true;
  }

  /// Switch a track to a built-in preset.
  void setPreset(int track, int presetIndex) {
    _trackCustomPath[track] = null;
    _trackPresetIndex[track] = presetIndex;
    _trackNames[track] = kDrumPresets[presetIndex].name;
  }

  /// Override a track with a user-picked file (name derived from filename).
  void setCustomPath(int track, String path) {
    _trackCustomPath[track] = path;
    final filename = path.split('/').last;
    _trackNames[track] = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;
  }

  /// Override a track with a known path and explicit display [name].
  void setCustomPathWithName(int track, String path, String name) {
    _trackCustomPath[track] = path;
    _trackNames[track] = name;
  }

  /// Clear custom file override; track reverts to its current preset.
  void clearCustomPath(int track) {
    _trackCustomPath[track] = null;
    _trackNames[track] = kDrumPresets[_trackPresetIndex[track]].name;
  }

  /// Set trim points for [track]. Pass [start] and optional [end].
  void setTrim(int track, Duration start, Duration? end) {
    _trimStart[track] = start;
    _trimEnd[track] = end;
  }

  /// Clear trim for [track]; sample plays from beginning to end.
  void clearTrim(int track) {
    _trimStart[track] = Duration.zero;
    _trimEnd[track] = null;
  }

  /// Returns the duration of the sample currently assigned to [track],
  /// or null if it cannot be determined.
  Future<Duration?> getTrackDuration(int track) async {
    if (!_ready) return null;
    final path = _trackCustomPath[track] ?? _presetPaths[_trackPresetIndex[track]];
    try {
      // Probe duration by setting source without playing.
      await _players[track].setSource(DeviceFileSource(path));
      return await _players[track].getDuration();
    } catch (e) {
      debugPrint('AudioEngine getDuration error: $e');
      return null;
    }
  }

  /// Trigger a one-shot hit on [track].
  ///
  /// Uses a generation counter so that if a newer trigger arrives while
  /// an async operation is in flight, the stale operation is abandoned.
  /// When trim points are set, the sample is seeked to [trimStart] before
  /// playback and a timer fires [stop()] at [trimEnd].
  Future<void> trigger(int track) async {
    if (!_ready) return;
    final gen = ++_triggerGen[track];
    _trimTimers[track]?.cancel();
    _trimTimers[track] = null;
    final path = _trackCustomPath[track] ?? _presetPaths[_trackPresetIndex[track]];
    try {
      final start = _trimStart[track];
      final end = _trimEnd[track];
      final trimmed = start != Duration.zero || end != null;

      await _players[track].stop();
      if (_triggerGen[track] != gen) return;

      if (trimmed) {
        await _players[track].setSource(DeviceFileSource(path));
        if (_triggerGen[track] != gen) return;
        await _players[track].setVolume(_trackVolume[track]);
        if (_triggerGen[track] != gen) return;
        await _players[track].seek(start);
        if (_triggerGen[track] != gen) return;
        await _players[track].resume();
        if (_triggerGen[track] != gen) return;
        if (end != null) {
          final playDuration = end - start;
          if (playDuration > Duration.zero) {
            _trimTimers[track] = Timer(playDuration, () {
              if (_triggerGen[track] == gen) {
                _players[track].stop();
              }
            });
          }
        }
      } else {
        await _players[track].play(
          DeviceFileSource(path),
          volume: _trackVolume[track],
        );
      }
    } catch (e) {
      debugPrint('AudioEngine trigger error: $e');
    }
  }

  Future<void> dispose() async {
    for (final t in _trimTimers) {
      t?.cancel();
    }
    for (final p in _players) {
      await p.dispose();
    }
    _players.clear();
  }
}
