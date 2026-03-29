# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
