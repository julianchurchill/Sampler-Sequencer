import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'dsp_utils.dart';

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
  DrumPreset('Kick 808',  generateKick808),
  DrumPreset('Kick Hard', generateKickHard),
  DrumPreset('Snare',     generateSnare),
  DrumPreset('Rim Shot',  generateRimShot),
  DrumPreset('HH Closed', generateHiHatClosed),
  DrumPreset('HH Open',   generateHiHatOpen),
  DrumPreset('Clap',      generateClap),
  DrumPreset('Tom',       generateTom),
  DrumPreset('Cowbell',   generateCowbell),
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

  /// Per-track mute flag (true = muted, no audio output).
  final List<bool> _trackMuted = List.filled(4, false);

  bool _ready = false;

  /// Monotonically increasing counter per track. When a new trigger arrives
  /// while a previous stop()→play() is in flight, the stale play() is skipped.
  final List<int> _triggerGen = List.filled(4, 0);

  bool get isReady => _ready;
  bool isMuted(int track) => _trackMuted[track];
  void setMuted(int track, bool muted) => _trackMuted[track] = muted;

  String trackName(int track) => _trackNames[track];
  bool hasCustomPath(int track) => _trackCustomPath[track] != null;
  String? customPath(int track) => _trackCustomPath[track];
  int presetIndex(int track) => _trackPresetIndex[track];
  double trackVolume(int track) => _trackVolume[track];
  /// Resolved sample path for [track] — custom file if set, otherwise the cached preset WAV.
  String samplePath(int track) =>
      _trackCustomPath[track] ?? _presetPaths[_trackPresetIndex[track]];
  Duration trimStart(int track) => _trimStart[track];
  Duration? trimEnd(int track) => _trimEnd[track];
  /// Stream of playback position updates for [track].
  Stream<Duration> positionStream(int track) => _players[track].onPositionChanged;
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
      final wavData = buildWav(kDrumPresets[i].generator(_kSampleRate), _kSampleRate);
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

    // Pre-load each track's source so that trigger() can seek+resume without
    // calling setSource() in the real-time path. This eliminates one
    // platform-channel round-trip (and MediaPlayer re-preparation) per hit.
    for (int i = 0; i < 4; i++) {
      await _players[i].setSource(DeviceFileSource(samplePath(i)));
    }

    _ready = true;
  }

  /// Switch a track to a built-in preset.
  void setPreset(int track, int presetIndex) {
    _trackCustomPath[track] = null;
    _trackPresetIndex[track] = presetIndex;
    _trackNames[track] = kDrumPresets[presetIndex].name;
    _scheduleSourceReload(track);
  }

  /// Override a track with a user-picked file (name derived from filename).
  void setCustomPath(int track, String path) {
    _trackCustomPath[track] = path;
    final filename = path.split('/').last;
    _trackNames[track] = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;
    _scheduleSourceReload(track);
  }

  /// Override a track with a known path and explicit display [name].
  void setCustomPathWithName(int track, String path, String name) {
    _trackCustomPath[track] = path;
    _trackNames[track] = name;
    _scheduleSourceReload(track);
  }

  /// Clear custom file override; track reverts to its current preset.
  void clearCustomPath(int track) {
    _trackCustomPath[track] = null;
    _trackNames[track] = kDrumPresets[_trackPresetIndex[track]].name;
    _scheduleSourceReload(track);
  }

  /// Fire-and-forget source reload for [track]. Called after any path change
  /// so that trigger() never needs to call setSource() in the real-time path.
  void _scheduleSourceReload(int track) {
    if (!_ready) return;
    _players[track]
        .setSource(DeviceFileSource(samplePath(track)))
        .catchError((Object e) {
      debugPrint('AudioEngine source reload error on track $track: $e');
    });
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

  /// Preview the sample on [track] using the supplied [start] and [end]
  /// positions (not the stored trim values). Intended for the trim editor UI.
  Future<void> previewTrim(int track, Duration start, Duration? end) async {
    if (!_ready) return;
    final gen = ++_triggerGen[track];
    _trimTimers[track]?.cancel();
    _trimTimers[track] = null;
    final path = samplePath(track);
    try {
      // Silence before stopping to prevent a click from an abrupt amplitude
      // cut mid-waveform. setVolume(0) takes effect at the next audio-buffer
      // boundary (~5 ms), so by the time stop() fires the output is already
      // at zero.
      await _players[track].setVolume(0.0);
      if (_triggerGen[track] != gen) return;
      await _players[track].stop();
      if (_triggerGen[track] != gen) return;
      // setSource() is required after stop() because Android MediaPlayer
      // transitions to Stopped state on stop(), from which seekTo() is invalid.
      // Calling setSource() moves it back through Initialized → Prepared,
      // making the subsequent seek() and resume() safe.
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
    } catch (e) {
      debugPrint('AudioEngine previewTrim error: $e');
    }
  }

  /// Stop playback on [track] (used to cancel a trim preview).
  Future<void> stopTrack(int track) async {
    if (!_ready) return;
    ++_triggerGen[track]; // cancel any in-flight trim timer
    _trimTimers[track]?.cancel();
    _trimTimers[track] = null;
    try {
      await _players[track].stop();
    } catch (e) {
      debugPrint('AudioEngine stopTrack error: $e');
    }
  }

  /// Stop all tracks immediately (e.g. when the sequencer is stopped).
  Future<void> stopAll() async {
    if (!_ready) return;
    for (int t = 0; t < _players.length; t++) {
      ++_triggerGen[t];
      _trimTimers[t]?.cancel();
      _trimTimers[t] = null;
    }
    await Future.wait([
      for (int t = 0; t < _players.length; t++)
        _players[t].stop().catchError((e) {
          debugPrint('AudioEngine stopAll error on track $t: $e');
          return;
        }),
    ]);
  }

  /// Trigger a one-shot hit on [track].
  ///
  /// Uses a generation counter so that if a newer trigger arrives while
  /// an async operation is in flight, the stale operation is abandoned.
  /// When trim points are set, the sample is seeked to [trimStart] before
  /// playback and a timer fires [stop()] at [trimEnd].
  Future<void> trigger(int track, {double velocity = 1.0}) async {
    if (!_ready) return;
    if (_trackMuted[track]) return;
    final gen = ++_triggerGen[track];
    _trimTimers[track]?.cancel();
    _trimTimers[track] = null;
    final path = samplePath(track);
    final effectiveVolume = (_trackVolume[track] * velocity.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    try {
      final start = _trimStart[track];
      final end = _trimEnd[track];
      final trimmed = start != Duration.zero || end != null;

      // Silence before stopping to prevent a click from an abrupt amplitude
      // cut mid-waveform (e.g. open hi-hat or cowbell retriggered rapidly).
      // setVolume(0) takes effect at the next audio-buffer boundary (~5 ms),
      // so by the time stop() fires the output is already at zero.
      await _players[track].setVolume(0.0);
      if (_triggerGen[track] != gen) return;
      await _players[track].stop();
      if (_triggerGen[track] != gen) return;

      if (trimmed) {
        // setSource() is required after stop() because Android MediaPlayer
        // transitions to Stopped state on stop(), from which seekTo() is
        // invalid. Calling setSource() moves it back through Initialized →
        // Prepared, making the subsequent seek() and resume() safe.
        await _players[track].setSource(DeviceFileSource(path));
        if (_triggerGen[track] != gen) return;
        await _players[track].setVolume(effectiveVolume);
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
        // play(Source) handles setSource + prepare + start in one call,
        // correctly resetting the MediaPlayer from Stopped → Playing state.
        await _players[track].play(
          DeviceFileSource(path),
          volume: effectiveVolume,
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
