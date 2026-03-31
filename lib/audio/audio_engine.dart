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
  /// Four sequencer players, one per track.
  ///
  /// Initialised as [PlayerMode.lowLatency] (Android SoundPool). Sources are
  /// pre-loaded into SoundPool memory so that [trigger] fires in ~1 ms with
  /// no per-hit prepare() overhead — essential for a drum machine.
  /// Tracks that have trim points set are switched to [PlayerMode.mediaPlayer]
  /// because SoundPool does not support seek().
  final List<AudioPlayer> _players = [];

  /// Tracks the current player mode for each sequencer player so that
  /// [trigger] can take the correct fast or trimmed code path.
  final List<PlayerMode> _playerModes =
      List.filled(4, PlayerMode.lowLatency);

  /// Dedicated mediaPlayer used for trim preview and duration probing.
  /// Kept separate so that seek-based operations are isolated from the
  /// latency-sensitive sequencer players.
  late AudioPlayer _previewPlayer;

  /// Generation counter for [previewTrim] — separate from [_triggerGen] so
  /// that sequencer triggers and preview operations don't cancel each other.
  int _previewGen = 0;
  Timer? _previewTimer;

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

  /// Timers used to stop trimmed playback at the trim end point.
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
  /// while a previous async chain is in flight, the stale chain is abandoned.
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

  /// Playback-position stream for [track]; sourced from the dedicated preview
  /// player which is the only player that performs seek-based playback.
  Stream<Duration> positionStream(int track) =>
      _previewPlayer.onPositionChanged;

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

    // Four low-latency sequencer players (Android SoundPool).
    // SoundPool pre-loads audio data into memory; play() fires in ~1 ms
    // with no per-hit prepare() call — essential for a drum machine.
    for (int i = 0; i < 4; i++) {
      final player = AudioPlayer();
      await player.setPlayerMode(PlayerMode.lowLatency);
      _players.add(player);
    }

    // Pre-load each track's source into SoundPool memory so the first
    // trigger fires immediately without any load delay.
    for (int i = 0; i < 4; i++) {
      await _players[i].setSource(DeviceFileSource(samplePath(i)));
    }

    // One dedicated mediaPlayer for trim preview and duration probing.
    // It is the only player that calls seek(); keeping it separate means
    // the sequencer players are never blocked by seek latency.
    _previewPlayer = AudioPlayer();
    await _previewPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    await _previewPlayer.setReleaseMode(ReleaseMode.stop);
    await _previewPlayer.setAudioContext(AudioContext(
      android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
    ));

    _ready = true;
  }

  // ---------------------------------------------------------------------------
  // Source / preset management
  // ---------------------------------------------------------------------------

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

  /// Reload the source for [track]'s sequencer player.
  /// Fire-and-forget; called after any path change.
  void _scheduleSourceReload(int track) {
    if (!_ready) return;
    _players[track]
        .setSource(DeviceFileSource(samplePath(track)))
        .catchError((Object e) {
      debugPrint('AudioEngine source reload error on track $track: $e');
    });
  }

  // ---------------------------------------------------------------------------
  // Trim management
  // ---------------------------------------------------------------------------

  /// Set trim points for [track].
  ///
  /// If any trim is applied, the sequencer player is switched from
  /// lowLatency to mediaPlayer so that seek() becomes available at trigger time.
  void setTrim(int track, Duration start, Duration? end) {
    _trimStart[track] = start;
    _trimEnd[track] = end;
    final hasTrimNow = start != Duration.zero || end != null;
    _schedulePlayerModeSwitch(
      track,
      hasTrimNow ? PlayerMode.mediaPlayer : PlayerMode.lowLatency,
    );
  }

  /// Clear trim for [track]; sample plays from beginning to end.
  ///
  /// Switches the sequencer player back to lowLatency for fast triggering.
  void clearTrim(int track) {
    _trimStart[track] = Duration.zero;
    _trimEnd[track] = null;
    _schedulePlayerModeSwitch(track, PlayerMode.lowLatency);
  }

  /// Asynchronously rebuild [track]'s sequencer player in [mode].
  /// Fire-and-forget so setTrim/clearTrim remain synchronous.
  void _schedulePlayerModeSwitch(int track, PlayerMode mode) {
    if (!_ready) return;
    if (_playerModes[track] == mode) return;
    _playerModes[track] = mode;
    _rebuildPlayer(track, mode).catchError((Object e) {
      debugPrint('AudioEngine mode switch error on track $track: $e');
    });
  }

  Future<void> _rebuildPlayer(int track, PlayerMode mode) async {
    final old = _players[track];
    final player = AudioPlayer();
    await player.setPlayerMode(mode);
    if (mode == PlayerMode.mediaPlayer) {
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setAudioContext(AudioContext(
        android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      ));
    }
    await player.setSource(DeviceFileSource(samplePath(track)));
    _players[track] = player;
    await old.dispose();
  }

  // ---------------------------------------------------------------------------
  // Duration / position
  // ---------------------------------------------------------------------------

  /// Returns the duration of the sample currently assigned to [track],
  /// or null if it cannot be determined.
  Future<Duration?> getTrackDuration(int track) async {
    if (!_ready) return null;
    final path = samplePath(track);
    try {
      await _previewPlayer.setSource(DeviceFileSource(path));
      return await _previewPlayer.getDuration();
    } catch (e) {
      debugPrint('AudioEngine getDuration error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  /// Preview the sample on [track] using the supplied [start] and [end]
  /// positions (not the stored trim values). Intended for the trim editor UI.
  ///
  /// Always uses [_previewPlayer] (mediaPlayer) so that seek() is available
  /// regardless of the sequencer player's current mode.
  Future<void> previewTrim(int track, Duration start, Duration? end) async {
    if (!_ready) return;
    final gen = ++_previewGen;
    _previewTimer?.cancel();
    _previewTimer = null;
    final path = samplePath(track);
    try {
      await _previewPlayer.setVolume(0.0);
      if (_previewGen != gen) return;
      await _previewPlayer.stop();
      if (_previewGen != gen) return;
      await _previewPlayer.setSource(DeviceFileSource(path));
      if (_previewGen != gen) return;
      await _previewPlayer.setVolume(_trackVolume[track]);
      if (_previewGen != gen) return;
      await _previewPlayer.seek(start);
      if (_previewGen != gen) return;
      await _previewPlayer.resume();
      if (_previewGen != gen) return;
      if (end != null) {
        final playDuration = end - start;
        if (playDuration > Duration.zero) {
          _previewTimer = Timer(playDuration, () {
            if (_previewGen == gen) {
              _previewPlayer.stop();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('AudioEngine previewTrim error: $e');
    }
  }

  /// Stop playback on [track] (cancels both a sequencer hit and any trim preview).
  Future<void> stopTrack(int track) async {
    if (!_ready) return;
    ++_triggerGen[track];
    _trimTimers[track]?.cancel();
    _trimTimers[track] = null;
    ++_previewGen;
    _previewTimer?.cancel();
    _previewTimer = null;
    try {
      await Future.wait([
        _players[track].stop().catchError((Object e) {
          debugPrint('AudioEngine stopTrack player error: $e');
        }),
        _previewPlayer.stop().catchError((Object e) {
          debugPrint('AudioEngine stopTrack preview error: $e');
        }),
      ]);
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
    ++_previewGen;
    _previewTimer?.cancel();
    _previewTimer = null;
    await Future.wait([
      for (int t = 0; t < _players.length; t++)
        _players[t].stop().catchError((e) {
          debugPrint('AudioEngine stopAll error on track $t: $e');
          return;
        }),
      _previewPlayer.stop().catchError((e) {
        debugPrint('AudioEngine stopAll preview error: $e');
        return;
      }),
    ]);
  }

  /// Trigger a one-shot hit on [track].
  ///
  /// **Untrimmed tracks** (lowLatency mode): [stop] + [play] with the
  /// pre-loaded SoundPool source — ~2 platform-channel calls, ~1 ms latency,
  /// no prepare() overhead. This eliminates the 30–100 ms gap that caused
  /// crackling on consecutive hits with the previous MediaPlayer approach.
  ///
  /// **Trimmed tracks** (mediaPlayer mode): the slower stop/setSource/seek/
  /// resume chain is unavoidable because SoundPool does not support seek().
  Future<void> trigger(int track, {double velocity = 1.0}) async {
    if (!_ready) return;
    if (_trackMuted[track]) return;
    final gen = ++_triggerGen[track];
    _trimTimers[track]?.cancel();
    _trimTimers[track] = null;
    final path = samplePath(track);
    final effectiveVolume =
        (_trackVolume[track] * velocity.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    try {
      final start = _trimStart[track];
      final end = _trimEnd[track];
      final trimmed = start != Duration.zero || end != null;

      if (!trimmed && _playerModes[track] == PlayerMode.lowLatency) {
        // Fast path: SoundPool source is pre-loaded in memory.
        // stop() cancels any previous play; play() fires in ~1 ms with no
        // prepare() call. No soft-stop setVolume(0) needed — SoundPool
        // stop() is a direct native call with no audio-thread buffering gap.
        await _players[track].stop();
        if (_triggerGen[track] != gen) return;
        await _players[track].play(
          DeviceFileSource(path),
          volume: effectiveVolume,
        );
      } else {
        // MediaPlayer path: required for trimmed playback (seek) or when a
        // clearTrim() mode switch back to lowLatency hasn't completed yet.
        if (trimmed && _playerModes[track] != PlayerMode.mediaPlayer) {
          // setTrim() was called but async rebuild hasn't finished yet.
          // Force a synchronous rebuild before proceeding.
          await _rebuildPlayer(track, PlayerMode.mediaPlayer);
          if (_triggerGen[track] != gen) return;
        }
        await _players[track].setVolume(0.0);
        if (_triggerGen[track] != gen) return;
        await _players[track].stop();
        if (_triggerGen[track] != gen) return;
        await _players[track].setSource(DeviceFileSource(path));
        if (_triggerGen[track] != gen) return;
        await _players[track].setVolume(effectiveVolume);
        if (_triggerGen[track] != gen) return;
        await _players[track].seek(trimmed ? start : Duration.zero);
        if (_triggerGen[track] != gen) return;
        await _players[track].resume();
        if (_triggerGen[track] != gen) return;
        if (trimmed && end != null) {
          final playDuration = end - start;
          if (playDuration > Duration.zero) {
            _trimTimers[track] = Timer(playDuration, () {
              if (_triggerGen[track] == gen) {
                _players[track].stop();
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('AudioEngine trigger error: $e');
    }
  }

  Future<void> dispose() async {
    _previewTimer?.cancel();
    for (final t in _trimTimers) {
      t?.cancel();
    }
    for (final p in _players) {
      await p.dispose();
    }
    _players.clear();
    await _previewPlayer.dispose();
  }
}
