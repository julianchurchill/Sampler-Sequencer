# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.3.6] - 2026-04-06

### Changed
- `_fireAndAdvance()` no longer calls `notifyListeners()` on every sequencer
  tick. The playhead step is now tracked via a `ValueNotifier<int>
  currentStepNotifier` on `SequencerModel`. `StepButton` subscribes via
  `ValueListenableBuilder`, so only the two buttons whose `isCurrent` state
  changes (previous step → false, new step → true) rebuild per tick instead
  of triggering all 64 `context.select` evaluations via `notifyListeners`.
  At 300 BPM this reduces per-tick selector work from 256 evaluations/tick
  to 2 widget rebuilds/tick.

## [Unreleased]

### Changed
- README Architecture section updated: directory tree now includes all current
  files (`audio_exporter.dart`, `audio_recorder.dart`, `dsp_utils.dart`,
  `sample_library.dart`, `wav_io.dart`, `export_sheet.dart`,
  `trim_editor_sheet.dart`, `pad_config_sheet.dart`); prose updated to describe
  the trim/media-player path and the ping-pong retrigger pool; Summary updated
  to mention WAV export, microphone recording, sample library, trim, velocity,
  and persistence; Frameworks table extended with `record`, `shared_preferences`,
  `share_plus`, `package_info_plus`, and `mocktail`; Permissions table updated
  to include `RECORD_AUDIO`.

## [2.3.5] - 2026-04-06

### Changed
- `trigger()` in `AudioEngine` split into three focused methods: `trigger()`
  dispatches to `_triggerFast()` (ping-pong SoundPool path) or
  `_triggerMediaPlayer()` (trimmed/mediaPlayer path), reducing cyclomatic
  complexity from ~14 to ~6 per method.
- `_SoundPickerSheetState` god-class broken up: recording state machine,
  recorder lifecycle, temp-path handling, and the name-after-recording dialog
  are extracted into a new private `_RecordSection` stateful widget, leaving
  `_SoundPickerSheetState` responsible only for rename and the sample list.

## [2.3.4] - 2026-04-06

### Changed
- Extracted a new `lib/audio/wav_io.dart` module containing all WAV I/O
  primitives (`WavData`, `writeWavHeader`, `pcmChunkToBytes`,
  `writeWavChunked`, `readWav`). Both `dsp_utils.dart` and
  `audio_exporter.dart` now import from this single source of truth,
  removing the duplicated WAV header format knowledge that existed when
  `AudioExporter` maintained its own private `_readWav`/`_WavData` in
  parallel with `buildWav` in `dsp_utils.dart`.
- `buildWav` refactored to delegate header construction to `writeWavHeader`;
  only the fade-envelope PCM loop is specific to `buildWav`.

## [2.3.3] - 2026-04-05

### Fixed
- `SequencerModel.init()` now guards against stale custom-sample paths stored
  in `SharedPreferences`: if a file no longer exists on disk the track falls
  back to its preset instead of passing a bad path to `AudioEngine`.
- `AudioEngine.getTrackDuration()` now stops the preview player before calling
  `setSource()`, preventing a race if the player was mid-playback.
- `AudioEngine.setTrackVolume()` applies volume to all slots in parallel
  (`Future.wait`) instead of sequentially, removing a ~6 round-trip delay.
- `SampleLibrary._loadIndex()` checks file existence for all index entries in
  parallel (`Future.wait`) instead of sequentially.
- Export error snackbar no longer leaks internal exception details to the user.

### Changed
- `SequencerModel.loadCustomSample2` renamed to `loadLibrarySample` to
  distinguish it clearly from `loadCustomSample` (which invokes the file picker).
- `SequencerModel.init()` refactored into two focused private helpers:
  `_restoreStepsAndBpm` and `_restoreTrackState`.
- `SampleEntry` fields (`path`, `name`) are now `final`; `rename()` replaces
  the entry via `copyWith` rather than mutating in place.
- Random seed literals in drum generators replaced with named constants
  (`_kSnareNoiseSeed`, `_kRimShotNoiseSeed`, etc.) explaining their role.
- `AudioEngine.initForTest` doc and assert updated to reference `kNumTracks`
  rather than the literal `4`.
- `AudioExporter.export` uses `kNumTracks`/`kNumSteps` constants instead of
  the literal `4`/`16`.
- Duplicated `effectiveEndMs` null-resolution logic in `_TrimEditorSheetState`
  extracted into a single `_effectiveEndMs()` helper.

### Tests
- `dspEnv` monotonicity test extended from [0, 50) to the full [0, 100) range.
- Added sample-count and amplitude-range tests for four previously uncovered
  drum generators: `generateRimShot`, `generateHiHatOpen`, `generateClap`,
  and `generateTom`.

## [2.3.2] - 2026-04-02

### Fixed
- `_save()` in `SequencerModel` no longer silently swallows `SharedPreferences`
  errors. Failures are now logged via `debugPrint` and surfaced as an `AlertDialog`
  so data-loss scenarios are immediately visible during development.

## [2.3.1] - 2026-04-02

### Changed
- `AudioEngine.slotsPerTrack` exposed as a public constant (was `_kSlotsPerTrack`).
- `AudioEngine.initForTest()` added (`@visibleForTesting`) so the trigger path
  can be exercised with mock players without platform channels or file I/O.

### Tests
- `test/audio_engine_trigger_test.dart` — four tests covering the trigger fast path:
  1. 16 consecutive trigger() calls each fire play() (regression guard for the 3/16 kicks bug)
  2. Ping-pong: each slot is stopped+played exactly once across slotsPerTrack triggers
  3. Muted track fires no play() calls
  4. Velocity is multiplied by track volume and passed to play()

## [2.3.0] - 2026-04-02

### Added
- Version info overlay: tapping the ⓘ button in the app bar shows a dialog
  with the app version, build number, and build timestamp. The timestamp is
  injected at CI build time via `--dart-define=BUILD_TIMESTAMP=...` and falls
  back to "dev" for local debug builds.

## [2.2.4] - 2026-04-02

### Fixed
- Eliminated click on the 2nd adjacent Kick 808 hit caused by two overlapping
  SoundPool streams summing to ~1.19× peak amplitude in the PCM mixer (hard
  clipping). Reduced Kick 808 amplitude from 0.9 to 0.72; two adjacent hits
  now sum to ≤ 0.95 at 120 BPM.
- Fixed silent kick drops (~3/16 heard) caused by two compounding bugs:
  1. `_scheduleSourceReload` queued unawaited `setSource()` calls in each
     player's command queue; `trigger()`'s `stop()` was serialised behind them
     and did not execute until the reload finished. By then the next step had
     incremented `_triggerGen`, and the generation check dropped the kick.
  2. The generation check between `stop()` and `play()` in the untrimmed
     ping-pong fast path is incorrect: every trigger uses a *different* slot,
     so there is no resource conflict to guard against.
  Fix: `setPreset` / `setCustomPath` / `setCustomPathWithName` / `clearCustomPath`
  now return `Future<void>` that resolves when all SoundPool slots have loaded.
  `SequencerModel.init()` awaits them so sources are fully loaded before the
  user can hit play. The generation check is removed from the fast path.

## [2.2.3] - 2026-04-01

### Fixed
- Fixed retrigger click regression introduced in 2.2.2: replacing `play(source)`
  with `setVolume()` + `resume()` caused `SoundPoolPlayer.resume()` to silently
  fail with "NotPrepared" because `stop()` resets the `prepared` flag that
  `resume()` checks before calling `start()`. Reverted to `play(source)` in the
  fast trigger path, which re-establishes `prepared` via `setSource()` before
  resuming — the only reliable way to restart a stopped SoundPool player.

## [Unreleased]

### Changed
- CI now signs release APKs with a persistent keystore stored as a GitHub
  Actions secret (`RELEASE_KEYSTORE_BASE64`). Previously the debug keystore
  was regenerated on every runner, so each build produced a differently-signed
  APK that Android refused to install over an existing installation.

## [2.2.2] - 2026-04-01

### Fixed
- Fixed audio quality degrading after prolonged playback, eventually causing
  retrigger clicks even on simple 2-step patterns. Root cause: the fast trigger
  path called `play(source)` on every hit, which internally calls `setSource()`
  each time. audioplayers' `SoundPoolManager` appends an entry to its
  `urlToPlayers` cache on every `setSource()` call — even on cache-hits — and
  never removes entries. After minutes of continuous playback the list grew to
  thousands of entries; lock contention on the synchronized cache block
  introduced timing jitter that caused `stop()` to arrive at SoundPool before
  the previous stream had fully decayed, producing a click. Fix: use
  `setVolume()` + `resume()` in the fast path instead, relying on the
  `setSource()` already called per slot in `init()`.
- Fixed click on the 6th+ consecutive Kick 808 hit. With 4 slots per track at
  120 BPM, slot reuse occurred at exactly 500 ms — the same as the Kick 808
  sample duration — creating a race between `stop()` and SoundPool's own
  natural-completion cleanup at the WAV fade-out boundary. Increased
  `_kSlotsPerTrack` from 4 to 6; slot reuse now occurs at 750 ms, 250 ms past
  every preset's natural end, ensuring `stop()` is always a confirmed no-op on
  an already-silent stream.

## [2.2.1] - 2026-03-31

### Fixed
- Eliminated retrigger click when the same sample is fired before the previous
  hit has decayed to silence (e.g. two Kick 808s on adjacent steps). Root cause:
  `stop()` on a SoundPool stream abruptly zeros the audio output at whatever
  amplitude the waveform is at, producing a sharp click transient. Fix: each
  track now uses two SoundPool players (ping-pong slots). On every trigger the
  engine advances to the next slot and stops only *that* slot's previous stream —
  from two or more triggers ago, so its amplitude is well into decay. The stream
  from the immediately preceding trigger is left to play out naturally; the
  waveform is never cut at peak amplitude. Four slots per track are used so
  that even long samples such as HH Open (600 ms) decay to ~5 % amplitude
  before their slot is reused at 120 BPM.

## [2.2.0] - 2026-03-31

### Changed
- Sequencer players switched from `PlayerMode.mediaPlayer` (Android MediaPlayer) to `PlayerMode.lowLatency` (Android SoundPool). Preset WAV data is loaded into SoundPool memory once at startup; each trigger costs ~2 platform-channel calls with no per-hit `prepare()` overhead (~1 ms latency vs. the previous 30–100 ms). This eliminates the gap that caused crackling on consecutive hits of the same track (e.g. two kick 808s in a row).
- A dedicated `_previewPlayer` in `mediaPlayer` mode is now the sole player that calls `seek()`. It handles trim preview, duration probing, and trimmed-track playback. This separation keeps seek latency out of the sequencer hot path entirely.
- Tracks with trim points set are transparently switched to a `mediaPlayer`-mode sequencer player (via `setTrim`) and back to `lowLatency` (via `clearTrim`) so that seek remains available for trimmed playback without affecting untrimmed tracks.

## [2.1.1] - 2026-03-30

### Fixed
- Reduced audio crackling on synthesised presets by applying a 256-sample (~5.8 ms) linear fade-in and fade-out when encoding generated WAV files. Noise-based sounds (snare, hi-hats, clap) previously produced a non-zero first sample that caused an audible click each time the player restarted.
- Eliminated click when a long sample (open hi-hat, cowbell) is cut off by a rapid retrigger on the same track. The player is now silenced via `setVolume(0)` immediately before `stop()`, ensuring the output is already at zero by the time the MediaPlayer transitions to stopped state.
- Removed `setSource()` from the real-time trigger path. Sources are pre-loaded in `init()` and reloaded only when the preset or file changes, cutting one platform-channel round-trip and a MediaPlayer re-preparation cycle from every hit.

## [2.1.0] - 2026-03-29

### Added
- Unit test suite: 30+ tests covering constants, `SequencerModel` logic (BPM clamping, step toggling, velocity, clear), and DSP utilities (WAV header, envelope, drum generators)
- `mocktail` dev dependency for mock-based testing without code generation
- `scripts/pre-commit.sh` and `scripts/install-hooks.sh` — run `sh scripts/install-hooks.sh` once after cloning to block commits when tests fail
- `flutter test` step added to CI so tests must pass before every APK build

### Changed
- DSP functions (`buildWav`, `dspEnv`, drum generators) extracted from `audio_engine.dart` into `lib/audio/dsp_utils.dart` so they are importable in tests
- `SequencerModel` now accepts an optional `AudioEngine` constructor parameter for dependency injection in tests; production behaviour is unchanged

## [2.0.0] - 2026-03-29

### Added
- Per-pad velocity: long-press any pad to open a configuration sheet and set its velocity (0–100%); velocity scales the track volume for that hit
- Dot indicator appears at the bottom of any pad whose settings differ from the default (velocity < 100%), visible on both active and inactive pads
- Velocity persists across app restarts; clearing all steps also resets all velocities to default

## [1.9.1] - 2026-03-29

### Changed
- Trim editor progress bar is now always visible, sitting at the start position when idle rather than only appearing during playback

## [1.9.0] - 2026-03-29

### Added
- Track muting: tap the speaker icon on any track label to instantly mute or unmute that track; muted tracks are silenced during sequencer playback and the track name dims to indicate mute state; mute state persists across app restarts
- Tapping the track name now opens the track settings sheet (previously any tap on the label area opened settings)

## [1.8.0] - 2026-03-29

### Changed
- Trim editor play button now shows a pause icon while previewing instead of a stop icon
- Trim editor shows a progress bar with a moving circular indicator while previewing, so you can see how far through the trimmed region playback has reached

## [1.7.0] - 2026-03-29

### Added
- Export N loops of the sequence to a 44100 Hz 16-bit stereo WAV via the share icon in the app bar; the OS share sheet lets the user save it to files, send it, or open it in a DAW
- Export sheet shows loop count (1–16), total duration preview, and a progress bar during rendering
- Tracks with non-WAV custom samples are silenced and flagged with a warning in the sheet
- Recordings are now saved as WAV instead of M4A, making them directly usable in the exporter and compatible with any audio tool

### Changed
- `share_plus` added as a dependency for sharing the exported file

## [1.6.0] - 2026-03-29

### Added
- Sample library now persists display names across app restarts via an `index.json` file in the library directory
- Recordings use timestamp-based filenames, eliminating name collision overwrites
- Rename no longer renames the file on disk — only the display name in the index is updated
- Existing libraries without an index are automatically migrated on first launch

## [1.5.3] - 2026-03-29

### Fixed
- Stop button now silences all playing samples immediately; previously long samples would continue until they finished naturally

## [1.5.2] - 2026-03-29

### Fixed
- Track sample and volume settings were not restored on app restart. `AudioEngine.init()` was only called lazily on first play, so the restore loop in `SequencerModel.init()` threw a `RangeError` when trying to set volume on uninitialised players, aborting the loop before most tracks were processed and preventing `notifyListeners()` from firing. The engine is now initialised eagerly at startup before state is restored.

## [1.5.1] - 2026-03-28

### Changed
- Track label now shows a single `tune` icon button instead of separate LOAD, TRIM, and volume controls; tapping it opens a track settings sheet containing volume slider, sound picker, and trim editor in one place
- Settings icon is tinted in the track colour when a custom sound or trim is active, providing at-a-glance status

## [1.5.0] - 2026-03-28

### Added
- Per-track non-destructive sample trimming: TRIM button opens an editor sheet with a range slider to set start and end points; the original file is never modified
- Trim state is persisted across app restarts
- Active trim is indicated by the TRIM button lighting up in the track colour; the × button clears it

### Changed
- Audio players switched from SoundPool (`lowLatency`) to MediaPlayer (`mediaPlayer`) mode to enable seek() support required for trim playback

## [1.4.0] - 2026-03-28

### Added
- Per-track volume slider in the track label area (0–100%); volume is persisted across app restarts

## [1.3.3] - 2026-03-28

### Fixed
- Track sample selections (preset choice, custom file path and name) are now persisted to `shared_preferences` and restored on next launch; previously only steps and BPM were saved

## [1.3.2] - 2026-03-28

### Fixed
- Triggering a sample no longer stops samples playing on other tracks; root cause was each AudioPlayer independently requesting `AUDIOFOCUS_GAIN`, causing Android to signal other in-app players to stop. Fixed by setting `AudioFocus.none` on all players
- Samples on the same track no longer overlap when re-triggered; a generation counter ensures a stale stop()→play() sequence is abandoned if a newer trigger has already started

## [1.3.1] - 2026-03-28

### Fixed
- Sequence steps and BPM are now persisted to `shared_preferences` and restored on next launch; previously the sequence was lost when the app was killed in the background

## [1.3.0] - 2026-03-28

### Added
- Record audio from the device microphone directly in the sound picker
- Persistent sample library — recordings are saved to app storage and survive restarts
- Rename saved samples via the pencil icon in the library list
- Delete saved samples via the trash icon
- Library samples can be loaded onto any track with the LOAD button
- Pulsing recording indicator while mic is active

## [1.2.0] - 2026-03-28

### Added
- Built-in preset sound library: Kick 808, Kick Hard, Snare, Rim Shot, HH Closed, HH Open, Clap, Tom, Cowbell
- LOAD button opens a sound picker sheet — choose a preset or browse for a custom audio file
- Track label updates to show the active preset or loaded filename

### Changed
- Tracks now always have a named preset active; custom files override the preset
- Clearing a custom file (×) reverts the track to its last selected preset

## [1.1.0] - 2026-03-28

### Added
- Load custom audio samples per track via the system file picker
- Display loaded sample filename (truncated) in each track label
- Clear custom sample with the × button to revert to the synthesised default

## [1.0.0] - 2026-03-28

### Added
- 4-track step sequencer with 16 steps per track
- Synthesised drum sounds (kick, snare, closed hi-hat, open hi-hat) generated in Dart — no bundled audio files required
- BPM control (40–300 BPM); long-press ±10 BPM shortcut
- Play/stop transport with immediate first-step trigger
- Clear all steps button
- GitHub Actions CI workflow producing a signed release APK artifact
