# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
