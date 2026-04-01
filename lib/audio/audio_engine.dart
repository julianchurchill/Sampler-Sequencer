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

/// Number of SoundPool player slots per sequencer track.
///
/// On each trigger the engine advances to the next slot (round-robin) and
/// stops only that slot's previous stream — from [_kSlotsPerTrack] triggers
/// ago. The stream from the immediately preceding trigger is left to play out
/// naturally, so the waveform is never cut at peak amplitude.
///
/// The value must satisfy two constraints:
///
/// 1. **Click threshold** — the stopped stream's amplitude must be near-zero:
///    `exp(-decayRate × elapsed / duration) < 0.05`. The worst case in the
///    preset library is HH Open (600 ms, decayRate 3.5). At 120 BPM (125 ms
///    per step) with 6 slots, elapsed = 6 × 125 = 750 ms:
///    - Kick 808 (500 ms, decayRate 4.0): `exp(-4.0 × 750/500) ≈ 0.25 %` ✓
///    - HH Open  (600 ms, decayRate 3.5): `exp(-3.5 × 750/600) ≈ 1.3 %`  ✓
///    - Cowbell  (800 ms, decayRate 6.0): `exp(-6.0 × 750/800) ≈ 1.1 %`  ✓
///
///    4 slots was not enough: slot reuse happened at exactly 500 ms for
///    Kick 808 — the same as its sample duration. `stop()` arrived in a
///    race with SoundPool's own natural-completion cleanup at the fade-out
///    boundary, occasionally producing a click on the 6th consecutive hit.
///    6 slots push the reuse point to 750 ms, well past every preset's end.
///
/// 2. **SoundPool stream budget** — 4 tracks × _kSlotsPerTrack players share
///    one SoundPool (maxStreams = 32). With 6 slots → 24 simultaneous streams
///    maximum, leaving headroom well below the 32-stream hard limit.
///
/// Do not reduce this value — see CLAUDE.md "Ping-pong retrigger".
const int _kSlotsPerTrack = 6;

class AudioEngine {
  /// Sequencer players — [_kSlotsPerTrack] per track.
  ///
  /// Player for track T, slot S lives at index T * _kSlotsPerTrack + S.
  ///
  /// All slots are initialised as [PlayerMode.lowLatency] (Android SoundPool).
  /// When a track has trim points the PRIMARY slot (S=0) is switched to
  /// [PlayerMode.mediaPlayer] so that seek() is available; the secondary slot
  /// (S=1) remains lowLatency but is unused while trim is active.
  final List<AudioPlayer> _players = [];

  /// Which slot within a track's player pair will be used on the NEXT trigger.
  /// Alternates between 0 and 1 on every untrimmed trigger.
  final List<int> _nextSlot = List.filled(4, 0);

  /// Tracks the current player mode for the PRIMARY slot of each track so
  /// that [trigger] can take the correct fast or trimmed code path.
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

  /// Primary player index for [track] (slot 0 — used for trimmed playback).
  int _primary(int track) => track * _kSlotsPerTrack;

  Future<void> setTrackVolume(int track, double volume) async {
    _trackVolume[track] = volume.clamp(0.0, 1.0);
    // Apply to both slots so whichever is currently playing reflects the change.
    for (int s = 0; s < _kSlotsPerTrack; s++) {
      await _players[track * _kSlotsPerTrack + s].setVolume(_trackVolume[track]);
    }
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

    // Two low-latency SoundPool players per track (8 total).
    //
    // Ping-pong retrigger: on each trigger the engine uses the NEXT slot and
    // stops only that slot's previous stream (from 2+ triggers ago, amplitude
    // well into decay). The slot used for the IMMEDIATELY preceding trigger is
    // left playing, so the waveform is never cut at peak amplitude — the root
    // cause of retrigger clicks on long samples such as Kick 808.
    //
    // AudioEngine invariants for every AudioPlayer created here or in
    // _rebuildPlayer() — see CLAUDE.md "AudioEngine invariants":
    //   • ReleaseMode.stop   — prevents shared SoundPool from being released
    //                          on sample completion (would silence all tracks).
    //   • AudioFocus.none    — prevents each trigger stealing focus from other
    //                          tracks via FocusManager (would cut them off).
    //   • PlayerMode         — lowLatency for sequencer (SoundPool, ~1 ms);
    //                          mediaPlayer for trim/preview (seek support).
    for (int i = 0; i < 4 * _kSlotsPerTrack; i++) {
      final player = AudioPlayer();
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setAudioContext(AudioContext(
        android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      ));
      _players.add(player);
    }

    // Pre-load each track's source into SoundPool memory for both slots so
    // the first trigger fires immediately without any load delay.
    for (int i = 0; i < 4; i++) {
      for (int s = 0; s < _kSlotsPerTrack; s++) {
        await _players[i * _kSlotsPerTrack + s]
            .setSource(DeviceFileSource(samplePath(i)));
      }
    }

    // One dedicated mediaPlayer for trim preview and duration probing.
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

  /// Reload the source for [track]'s sequencer players (all slots).
  /// Fire-and-forget; called after any path change.
  void _scheduleSourceReload(int track) {
    if (!_ready) return;
    for (int s = 0; s < _kSlotsPerTrack; s++) {
      _players[track * _kSlotsPerTrack + s]
          .setSource(DeviceFileSource(samplePath(track)))
          .catchError((Object e) {
        debugPrint('AudioEngine source reload error on track $track slot $s: $e');
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Trim management
  // ---------------------------------------------------------------------------

  /// Set trim points for [track].
  ///
  /// If any trim is applied, the primary sequencer player is switched from
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
  /// Switches the primary sequencer player back to lowLatency for fast triggering.
  void clearTrim(int track) {
    _trimStart[track] = Duration.zero;
    _trimEnd[track] = null;
    _schedulePlayerModeSwitch(track, PlayerMode.lowLatency);
  }

  /// Asynchronously rebuild [track]'s primary sequencer player in [mode].
  /// Fire-and-forget so setTrim/clearTrim remain synchronous.
  void _schedulePlayerModeSwitch(int track, PlayerMode mode) {
    if (!_ready) return;
    if (_playerModes[track] == mode) return;
    _playerModes[track] = mode;
    _rebuildPlayer(track, mode).catchError((Object e) {
      debugPrint('AudioEngine mode switch error on track $track: $e');
    });
  }

  /// Rebuild the PRIMARY player for [track] in [mode].
  ///
  /// Only the primary slot (S=0) is ever rebuilt — it switches between
  /// lowLatency (untrimmed) and mediaPlayer (trimmed). The secondary slot
  /// (S=1) always remains lowLatency.
  Future<void> _rebuildPlayer(int track, PlayerMode mode) async {
    final idx = _primary(track);
    final old = _players[idx];
    final player = AudioPlayer();
    await player.setPlayerMode(mode);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setAudioContext(AudioContext(
      android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
    ));
    await player.setSource(DeviceFileSource(samplePath(track)));
    _players[idx] = player;
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
    _nextSlot[track] = 0;
    _trimTimers[track]?.cancel();
    _trimTimers[track] = null;
    ++_previewGen;
    _previewTimer?.cancel();
    _previewTimer = null;
    try {
      final stops = <Future<void>>[
        for (int s = 0; s < _kSlotsPerTrack; s++)
          _players[track * _kSlotsPerTrack + s].stop().catchError((Object e) {
            debugPrint('AudioEngine stopTrack player error (slot $s): $e');
          }),
        _previewPlayer.stop().catchError((Object e) {
          debugPrint('AudioEngine stopTrack preview error: $e');
        }),
      ];
      await Future.wait(stops);
    } catch (e) {
      debugPrint('AudioEngine stopTrack error: $e');
    }
  }

  /// Stop all tracks immediately (e.g. when the sequencer is stopped).
  Future<void> stopAll() async {
    if (!_ready) return;
    for (int t = 0; t < 4; t++) {
      ++_triggerGen[t];
      _nextSlot[t] = 0;
      _trimTimers[t]?.cancel();
      _trimTimers[t] = null;
    }
    ++_previewGen;
    _previewTimer?.cancel();
    _previewTimer = null;
    await Future.wait([
      for (int i = 0; i < _players.length; i++)
        _players[i].stop().catchError((e) {
          debugPrint('AudioEngine stopAll error on player $i: $e');
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
  /// **Untrimmed tracks** (lowLatency mode): ping-pong between two SoundPool
  /// players. On each trigger the engine advances to the next slot and stops
  /// only that slot's previous stream — from two or more triggers ago, so its
  /// amplitude is well into the decay curve. The stream from the immediately
  /// preceding trigger is left to play out naturally; the waveform is never
  /// cut at peak amplitude, eliminating the retrigger click.
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
        // Ping-pong fast path.
        //
        // Advance to the next slot. The slot we are about to use held the
        // stream from _kSlotsPerTrack triggers ago — enough time for the
        // sample to have decayed significantly, so stopping it now is
        // inaudible (or near-inaudible). The OTHER slot's stream (from the
        // most recent trigger) is left untouched and plays out naturally.
        final slot = _nextSlot[track];
        _nextSlot[track] = (slot + 1) % _kSlotsPerTrack;
        final player = _players[track * _kSlotsPerTrack + slot];

        // stop() nullifies the internal streamId so the next start() call
        // creates a fresh SoundPool stream via soundPool.play(soundId, ...).
        await player.stop();
        if (_triggerGen[track] != gen) return;
        // Use setVolume + resume rather than play(source) here.
        //
        // play(source) calls setSource() internally on every trigger.
        // audioplayers' SoundPoolManager.urlToPlayers cache appends an entry
        // on EVERY setSource() call — even cache-hits — and never removes them.
        // After a few minutes of continuous playback the list has thousands of
        // entries; the synchronized(urlToPlayers) block becomes contended across
        // all 4 × 6 = 24 concurrent platform-channel calls, introducing timing
        // jitter that causes stop() to arrive at SoundPool before the previous
        // stream has fully decayed → click. setSource() was already called for
        // each slot in init() and is repeated by _scheduleSourceReload() on any
        // path change, so soundId is pre-established. After stop() nullifies
        // streamId, resume() → start() → soundPool.play(soundId, volume, ...)
        // starts a fresh stream with no repeated loading or cache pollution.
        await player.setVolume(effectiveVolume);
        if (_triggerGen[track] != gen) return;
        await player.resume();
      } else {
        // MediaPlayer path: required for trimmed playback (seek) or when a
        // clearTrim() mode switch back to lowLatency hasn't completed yet.
        final player = _players[_primary(track)];
        if (trimmed && _playerModes[track] != PlayerMode.mediaPlayer) {
          await _rebuildPlayer(track, PlayerMode.mediaPlayer);
          if (_triggerGen[track] != gen) return;
        }
        await player.setVolume(0.0);
        if (_triggerGen[track] != gen) return;
        await player.stop();
        if (_triggerGen[track] != gen) return;
        await player.setSource(DeviceFileSource(path));
        if (_triggerGen[track] != gen) return;
        await player.setVolume(effectiveVolume);
        if (_triggerGen[track] != gen) return;
        await player.seek(trimmed ? start : Duration.zero);
        if (_triggerGen[track] != gen) return;
        await player.resume();
        if (_triggerGen[track] != gen) return;
        if (trimmed && end != null) {
          final playDuration = end - start;
          if (playDuration > Duration.zero) {
            _trimTimers[track] = Timer(playDuration, () {
              if (_triggerGen[track] == gen) {
                _players[_primary(track)].stop();
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
