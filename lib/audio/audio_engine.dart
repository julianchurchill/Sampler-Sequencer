import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import 'dsp_utils.dart';

// ---------------------------------------------------------------------------
// AudioEngine
// ---------------------------------------------------------------------------

const int _kSampleRate = 44100;

/// Increment this constant whenever any drum generator in dsp_utils.dart is
/// changed so that stale WAV files cached from a previous app version are
/// automatically regenerated on next launch.
const int _kPresetCacheVersion = 1;

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
  /// Public alias for the number of SoundPool player slots per track.
  /// Exposed so that tests can create the right number of fake players via
  /// [initForTest] without depending on the private constant.
  static const int slotsPerTrack = _kSlotsPerTrack;

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
  final List<int> _nextSlot = List.filled(kNumTracks, 0);

  /// Tracks the current player mode for the PRIMARY slot of each track so
  /// that [trigger] can take the correct fast or trimmed code path.
  final List<PlayerMode> _playerModes =
      List.filled(kNumTracks, PlayerMode.lowLatency);

  /// Dedicated mediaPlayer used for trim preview and duration probing.
  /// Kept separate so that seek-based operations are isolated from the
  /// latency-sensitive sequencer players.
  late AudioPlayer _previewPlayer;

  /// Generation counter for [previewTrim] — separate from [_triggerGen] so
  /// that sequencer triggers and preview operations don't cancel each other.
  int _previewGen = 0;
  Timer? _previewTimer;

  /// Whether the preview player is currently playing a trim preview.
  /// Used to guard [getTrackDuration] against clobbering the preview player's
  /// source mid-playback.
  bool _previewPlaying = false;

  /// One cached WAV path per preset, indexed by kDrumPresets index.
  final List<String> _presetPaths = [];

  /// Per-track active preset index.
  final List<int> _trackPresetIndex = List.from(kDefaultPresetIndices);

  /// Per-track custom file override (null = use preset).
  final List<String?> _trackCustomPath = List.filled(kNumTracks, null);

  /// Per-track volume (0.0–1.0, default 1.0).
  final List<double> _trackVolume = List.filled(kNumTracks, 1.0);

  /// Per-track trim start (default Duration.zero).
  final List<Duration> _trimStart = List.filled(kNumTracks, Duration.zero);

  /// Per-track trim end (null = play to end of sample).
  final List<Duration?> _trimEnd = List.filled(kNumTracks, null);

  /// Timers used to stop trimmed playback at the trim end point.
  final List<Timer?> _trimTimers = List.filled(kNumTracks, null);

  /// Per-track display name shown in the UI.
  final List<String> _trackNames = List.generate(
    kNumTracks,
    (i) => kDrumPresets[kDefaultPresetIndices[i]].name,
  );

  /// Per-track mute flag (true = muted, no audio output).
  final List<bool> _trackMuted = List.filled(kNumTracks, false);

  /// Per-track in-flight rebuild future. When `_schedulePlayerModeSwitch`
  /// launches `_rebuildPlayer`, the future is stored here so that `trigger()`
  /// can await it before using a partially-initialised player.
  final List<Future<void>?> _pendingRebuild = List.filled(kNumTracks, null);

  /// Per-track cached source path for the primary (slot 0) player.
  ///
  /// Prevents redundant `setSource()` calls in the trimmed trigger path.
  /// audioplayers' `SoundPoolManager.urlToPlayers` appends an entry on every
  /// `setSource()` call (even cache-hits) and never removes them — after
  /// minutes of continuous playback lock contention causes timing jitter and
  /// clicks. By caching the last path set, `trigger()` only calls `setSource()`
  /// when the path has actually changed.
  final List<String?> _primarySourcePath = List.filled(kNumTracks, null);

  bool _ready = false;

  /// Monotonically increasing counter per track. When a new trigger arrives
  /// while a previous async chain is in flight, the stale chain is abandoned.
  final List<int> _triggerGen = List.filled(kNumTracks, 0);

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

  /// Playback-position stream sourced from the dedicated preview player,
  /// which is the only player that performs seek-based playback.
  Stream<Duration> get positionStream => _previewPlayer.onPositionChanged;

  bool hasTrim(int track) =>
      _trimStart[track] != Duration.zero || _trimEnd[track] != null;

  /// Primary player index for [track] (slot 0 — used for trimmed playback).
  int _primary(int track) => track * _kSlotsPerTrack;

  Future<void> setTrackVolume(int track, double volume) {
    _trackVolume[track] = volume.clamp(0.0, 1.0);
    // Apply to all slots in parallel so whichever is currently playing
    // reflects the change without serialising 6 round-trips.
    return Future.wait([
      for (int s = 0; s < _kSlotsPerTrack; s++)
        _players[track * _kSlotsPerTrack + s].setVolume(_trackVolume[track]),
    ]);
  }

  /// Test-only initialiser — bypasses file I/O and platform channels.
  ///
  /// Injects pre-built [players] (must have exactly
  /// `kNumTracks × [slotsPerTrack]` entries, track T owning slots
  /// `[T*slotsPerTrack .. T*slotsPerTrack + slotsPerTrack - 1]`) and a
  /// [previewPlayer], then marks the engine ready. Optionally accepts
  /// [presetPaths]; if omitted, placeholder paths are used — sufficient for
  /// tests that mock [AudioPlayer] and never touch the file system.
  @visibleForTesting
  void initForTest({
    required List<AudioPlayer> players,
    required AudioPlayer previewPlayer,
    List<String>? presetPaths,
  }) {
    assert(
      players.length == kNumTracks * _kSlotsPerTrack,
      'initForTest expects ${kNumTracks * _kSlotsPerTrack} players '
      '($kNumTracks tracks × $_kSlotsPerTrack slots), got ${players.length}',
    );
    _players.addAll(players);
    _previewPlayer = previewPlayer;
    final paths = presetPaths ??
        [for (int i = 0; i < kDrumPresets.length; i++) '/fake/preset_$i.wav'];
    _presetPaths.addAll(paths);
    _ready = true;
  }

  Future<void> init() async {
    if (_ready) return; // Idempotency guard — init() must only run once.

    // Cache synthesised presets to the application support directory so they
    // survive across cold starts.  A version marker file records which generator
    // version wrote the cache; on mismatch the files are regenerated.
    final supportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${supportDir.path}/presets');
    await cacheDir.create(recursive: true);
    final versionFile = File('${cacheDir.path}/version');
    final cachedVersion =
        await versionFile.exists() ? await versionFile.readAsString() : null;

    if (cachedVersion == '$_kPresetCacheVersion') {
      // Cache is current — use the existing files.
      for (int i = 0; i < kDrumPresets.length; i++) {
        _presetPaths.add('${cacheDir.path}/preset_$i.wav');
      }
    } else {
      // Cache is missing or stale — (re)synthesise all presets.
      for (int i = 0; i < kDrumPresets.length; i++) {
        final wavData = buildWav(kDrumPresets[i].generator(_kSampleRate), _kSampleRate);
        final path = '${cacheDir.path}/preset_$i.wav';
        await File(path).writeAsBytes(wavData);
        _presetPaths.add(path);
      }
      await versionFile.writeAsString('$_kPresetCacheVersion');
    }

    // _kSlotsPerTrack (6) low-latency SoundPool players per track
    // (kNumTracks × _kSlotsPerTrack = 24 total).
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
    for (int i = 0; i < kNumTracks * _kSlotsPerTrack; i++) {
      final player = AudioPlayer();
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      ));
      _players.add(player);
    }

    // Pre-load each track's source into SoundPool memory for both slots so
    // the first trigger fires immediately without any load delay.
    for (int i = 0; i < kNumTracks; i++) {
      for (int s = 0; s < _kSlotsPerTrack; s++) {
        await _players[i * _kSlotsPerTrack + s]
            .setSource(DeviceFileSource(samplePath(i)));
      }
      _primarySourcePath[i] = samplePath(i);
    }

    // One dedicated mediaPlayer for trim preview and duration probing.
    _previewPlayer = AudioPlayer();
    await _previewPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    await _previewPlayer.setReleaseMode(ReleaseMode.stop);
    await _previewPlayer.setAudioContext(AudioContext(
      android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
    ));

    _ready = true;
  }

  // ---------------------------------------------------------------------------
  // Source / preset management
  // ---------------------------------------------------------------------------

  /// Switch a track to a built-in preset.
  ///
  /// Returns a [Future] that completes once every sequencer player slot for
  /// [track] has finished loading the new source into SoundPool memory.
  /// Callers that do not need to wait (e.g. UI event handlers) may discard the
  /// Future; [SequencerModel.init] awaits it so playback is never attempted
  /// before the sources are ready.
  Future<void> setPreset(int track, int presetIndex) {
    _trackCustomPath[track] = null;
    _trackPresetIndex[track] = presetIndex;
    _trackNames[track] = kDrumPresets[presetIndex].name;
    return _reloadSourceForTrack(track);
  }

  /// Override a track with a user-picked file (name derived from filename).
  /// See [setPreset] for Future semantics.
  Future<void> setCustomPath(int track, String path) {
    _trackCustomPath[track] = path;
    final filename = path.split('/').last;
    _trackNames[track] = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;
    return _reloadSourceForTrack(track);
  }

  /// Override a track with a known path and explicit display [name].
  /// See [setPreset] for Future semantics.
  Future<void> setCustomPathWithName(int track, String path, String name) {
    _trackCustomPath[track] = path;
    _trackNames[track] = name;
    return _reloadSourceForTrack(track);
  }

  /// Clear custom file override; track reverts to its current preset.
  /// See [setPreset] for Future semantics.
  Future<void> clearCustomPath(int track) {
    _trackCustomPath[track] = null;
    _trackNames[track] = kDrumPresets[_trackPresetIndex[track]].name;
    return _reloadSourceForTrack(track);
  }

  /// Reload all sequencer player slots for [track] with the current
  /// [samplePath]. Returns a Future that completes when all slots have
  /// finished loading so that [trigger] never calls soundPool.play() on a
  /// sound that is still being loaded (which returns stream-id 0 and is
  /// silently dropped by SoundPool).
  Future<void> _reloadSourceForTrack(int track) {
    if (!_ready) return Future.value();
    return Future.wait([
      for (int s = 0; s < _kSlotsPerTrack; s++)
        _players[track * _kSlotsPerTrack + s]
            .setSource(DeviceFileSource(samplePath(track)))
            .catchError((Object e) {
          debugPrint('AudioEngine source reload error on track $track slot $s: $e');
        }),
    ]);
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
    late final Future<void> future;
    future = _rebuildPlayer(track, mode).catchError((Object e) {
      debugPrint('AudioEngine mode switch error on track $track: $e');
    }).whenComplete(() {
      // Clear the pending rebuild only if it is still the same future
      // (a newer rebuild may have been scheduled in the meantime).
      if (_pendingRebuild[track] == future) {
        _pendingRebuild[track] = null;
      }
    });
    _pendingRebuild[track] = future;
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
      android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
    ));
    await player.setSource(DeviceFileSource(samplePath(track)));
    _primarySourcePath[track] = samplePath(track);
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
    // Don't clobber the preview player's source if a trim preview is playing.
    if (_previewPlaying) return null;
    final path = samplePath(track);
    try {
      await _previewPlayer.stop();
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
      _previewPlaying = true;
      if (end != null) {
        final playDuration = end - start;
        if (playDuration > Duration.zero) {
          _previewTimer = Timer(playDuration, () {
            if (_previewGen == gen) {
              _previewPlaying = false;
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
    _previewPlaying = false;
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
    for (int t = 0; t < kNumTracks; t++) {
      ++_triggerGen[t];
      _nextSlot[t] = 0;
      _trimTimers[t]?.cancel();
      _trimTimers[t] = null;
    }
    ++_previewGen;
    _previewTimer?.cancel();
    _previewTimer = null;
    _previewPlaying = false;
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
  /// **Untrimmed tracks** (lowLatency mode): dispatches to [_triggerFast] —
  /// ping-pong between SoundPool players so the waveform is never cut at peak
  /// amplitude (no retrigger click).
  ///
  /// **Trimmed tracks** (mediaPlayer mode): dispatches to [_triggerMediaPlayer]
  /// — the slower stop/setSource/seek/resume chain is unavoidable because
  /// SoundPool does not support seek().
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
        await _triggerFast(track, path, effectiveVolume);
      } else {
        await _triggerMediaPlayer(
          track, path, effectiveVolume, gen,
          start: start, end: end, trimmed: trimmed,
        );
      }
    } catch (e) {
      debugPrint('AudioEngine trigger error: $e');
    }
  }

  /// Ping-pong fast path for untrimmed, lowLatency-mode tracks.
  ///
  /// Advances to the next slot (round-robin). The slot we are about to reuse
  /// held the stream from [_kSlotsPerTrack] triggers ago — well into amplitude
  /// decay — so stopping it is inaudible. The immediately preceding slot is
  /// left to play out naturally; the waveform is never cut at peak amplitude.
  ///
  /// Uses `play(source)` — do NOT replace with `setVolume()+resume()`.
  /// `SoundPoolPlayer.resume()` checks a `prepared` flag before calling
  /// `start()`; `stop()` resets it, so `resume()` after `stop()` silently
  /// errors with "NotPrepared". `play(source)` calls `setSource()` first,
  /// re-establishing `prepared` via the urlToPlayers cache — the only reliable
  /// restart path.
  ///
  /// No generation check between `stop()` and `play()`: each trigger uses a
  /// DIFFERENT ping-pong slot, so concurrent triggers never share a player.
  Future<void> _triggerFast(
    int track,
    String path,
    double effectiveVolume,
  ) async {
    final slot = _nextSlot[track];
    _nextSlot[track] = (slot + 1) % _kSlotsPerTrack;
    final player = _players[track * _kSlotsPerTrack + slot];
    await player.stop();
    await player.play(DeviceFileSource(path), volume: effectiveVolume);
  }

  /// MediaPlayer path for trimmed tracks or when a lowLatency→mediaPlayer
  /// mode switch is still in-flight.
  ///
  /// Awaits any pending [_rebuildPlayer] before touching the player, guards
  /// every async gap with a generation check ([gen]) to discard stale chains,
  /// and skips [setSource] when the path hasn't changed to avoid leaking
  /// entries into audioplayers' `urlToPlayers` cache.
  Future<void> _triggerMediaPlayer(
    int track,
    String path,
    double effectiveVolume,
    int gen, {
    required Duration start,
    required Duration? end,
    required bool trimmed,
  }) async {
    if (_pendingRebuild[track] != null) {
      await _pendingRebuild[track];
      if (_triggerGen[track] != gen) return;
      _pendingRebuild[track] = null;
    }
    final player = _players[_primary(track)];
    if (trimmed && _playerModes[track] != PlayerMode.mediaPlayer) {
      await _rebuildPlayer(track, PlayerMode.mediaPlayer);
      if (_triggerGen[track] != gen) return;
    }
    await player.setVolume(0.0);
    if (_triggerGen[track] != gen) return;
    await player.stop();
    if (_triggerGen[track] != gen) return;
    // Only call setSource() when the path has changed — audioplayers'
    // urlToPlayers cache leaks an entry on every setSource() call.
    if (_primarySourcePath[track] != path) {
      await player.setSource(DeviceFileSource(path));
      _primarySourcePath[track] = path;
      if (_triggerGen[track] != gen) return;
    }
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
