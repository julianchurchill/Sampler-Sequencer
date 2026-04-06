# Sampler Sequencer

A hardware-style drum machine and step sequencer for Android, built with Flutter.

![Platform](https://img.shields.io/badge/platform-Android-green)
![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)
![CI](https://github.com/julianchurchill/Sampler-Sequencer/actions/workflows/build.yml/badge.svg?branch=main)

---

## Summary

Sampler Sequencer is a 4-track, 16-step drum machine that runs in landscape orientation on Android. Each track can be assigned any of 9 synthesised drum presets generated in Dart from PCM maths (no audio files are bundled), a sample recorded via the microphone, or any audio file from device storage.

**Key features:**

- 4 tracks, 16-step grid, BPM control (40–300 BPM) with up/down buttons (long-press for ±10 jumps)
- 9 built-in synthesised drum presets: Kick 808, Kick Hard, Snare, Rim Shot, HH Closed, HH Open, Clap, Tom, Cowbell
- Per-track volume and mute; per-step velocity
- Record custom samples via microphone with an in-app library for managing recordings
- Load any audio file from device storage per track
- Trim each track's sample to a custom start/end window
- Export the current pattern as a mixed-down WAV file and share via the Android share sheet
- Settings (pattern, BPM, samples, volumes, trim) persist across app restarts
- Dark hardware-style UI, landscape-only

---

## Architecture

```
lib/
├── main.dart                      # Entry point; forces landscape, sets up Provider
├── constants.dart                 # Colours, BPM limits, step counts, drum presets
├── audio/
│   ├── audio_engine.dart          # Playback orchestration: SoundPool (sequencer) +
│   │                              #   MediaPlayer (trim/preview), ping-pong retrigger
│   ├── audio_exporter.dart        # Mix-down all 4 tracks to a WAV file for sharing
│   ├── audio_recorder.dart        # Thin wrapper around the `record` package
│   ├── dsp_utils.dart             # PCM synthesis for all 9 drum presets
│   ├── sample_library.dart        # Persisted list of user recordings (JSON index)
│   └── wav_io.dart                # WAV format primitives: header, chunked write, read
├── models/
│   └── sequencer_model.dart       # ChangeNotifier; Timer-based step sequencing,
│                                  #   SharedPreferences persistence
├── screens/
│   └── sequencer_screen.dart      # Root screen (AppBar + tracks + transport)
└── widgets/
    ├── export_sheet.dart          # Bottom sheet: export pattern to WAV
    ├── pad_config_sheet.dart      # (reserved for future per-pad config)
    ├── step_button.dart           # Individual step toggle with playhead highlight
    ├── track_row.dart             # Track label, settings/sound-picker sheets,
    │                              #   16 StepButtons
    ├── transport_bar.dart         # Play/Stop, BPM display, CLEAR, Export buttons
    └── trim_editor_sheet.dart     # Waveform-less trim editor: set start/end points
```

**State management:** `provider` — `SequencerModel` is a `ChangeNotifier` exposed via `ChangeNotifierProvider`. Each `StepButton` uses `context.select` so only the affected button rebuilds on state change.

**Sequencing:** `Timer.periodic` fires every `60,000,000 / (bpm × 4)` microseconds (one 16th-note step). On each tick the model triggers active tracks via `AudioEngine` then notifies the UI.

**Sound synthesis:** `dsp_utils.dart` generates raw PCM samples in Dart for each of the 9 drum presets. `AudioEngine.init()` writes them as 16-bit mono WAV files to the device's temp directory on startup, then loads them into Android `SoundPool` via `AudioPlayer(PlayerMode.lowLatency)` from the `audioplayers` package for ~1 ms trigger latency.

**Trim / media player path:** when a track has trim points set, its primary sequencer player is rebuilt as `PlayerMode.mediaPlayer` so that `seek()` is available. A pool of 6 SoundPool players per track (24 total) handles rapid retriggering without audible clicks on the untrimmed fast path.

---

## Frameworks & Libraries

| Package | Version | Purpose |
|---|---|---|
| `flutter` | SDK | UI framework |
| `audioplayers` | ^6.0.0 | Low-latency audio playback (Android `SoundPool` / `MediaPlayer`) |
| `provider` | ^6.1.1 | Lightweight state management |
| `file_picker` | ^8.0.0 | Load custom audio samples from device storage |
| `path_provider` | ^2.1.0 | Locate temp and documents directories |
| `record` | ^6.0.0 | Microphone recording for custom samples |
| `shared_preferences` | ^2.0.0 | Persist pattern, BPM, volumes, and sample selections |
| `share_plus` | ^10.0.0 | Share exported WAV via Android share sheet |
| `package_info_plus` | ^8.0.0 | Display app version in UI |
| `flutter_lints` | ^3.0.0 | (dev) Lint rules |
| `mocktail` | ^1.0.4 | (dev) Mock objects for unit tests |

**Build toolchain:**

- Flutter 3.x (stable channel)
- Gradle 8.14 with Kotlin DSL build files
- Android Gradle Plugin 8.11.1
- Kotlin 2.2.20
- Java 17
- `compileSdkVersion` 36, `minSdkVersion` 24 (Android 7.0+)

---

## Building

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
- Android SDK with platform 36 and build-tools (managed automatically by Gradle)
- Java 17+

### Build a release APK

```bash
git clone https://github.com/julianchurchill/Sampler-Sequencer.git
cd Sampler-Sequencer
flutter pub get
flutter build apk --release
```

The APK is output to:
```
build/app/outputs/flutter-apk/app-release.apk
```

Sideload it to a device with:
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Run on a connected device

```bash
flutter run --release
```

### CI build (GitHub Actions)

Every push triggers `.github/workflows/build.yml`, which builds a release APK and uploads it as a downloadable workflow artifact (`sampler-sequencer-release`). Find it under the **Actions** tab of the repository.

---

## Development Workflow

See [`CLAUDE.md`](CLAUDE.md) for the full branching policy. In short:

1. **Never commit directly to `main`.**
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Push and open a pull request targeting `main`.
4. The CI build must pass before merging.

---

## Troubleshooting

### No sound on device

- The app generates WAV files in the device temp directory on first play. If this fails silently, check that the app has storage permissions (or that the temp directory is writable — it always should be).
- `PlayerMode.lowLatency` uses Android's `SoundPool`, which has a maximum sample duration of ~5 seconds and works best with short PCM files. The synthesised sounds are well within this limit; very long custom samples may not load correctly.

### Custom sample does not play

- Only uncompressed or lightly-compressed formats are guaranteed by `SoundPool` (WAV, OGG). MP3 may work on some devices but is not reliable with `lowLatency` mode. If a custom sample does not trigger, try converting it to WAV or OGG first.
- On Android 13+ (API 33+) the app requests `READ_MEDIA_AUDIO`. On older versions it requests `READ_EXTERNAL_STORAGE` (capped at API 32). If the permission dialog does not appear, check app permissions in device settings.

### Gradle / build errors

- Ensure you have Java 17 set as `JAVA_HOME`. Earlier versions are not compatible with AGP 8.x.
- `flutter doctor -v` will diagnose most environment issues.
- The `android/local.properties` file is git-ignored and is written automatically by `flutter build` / `flutter run`. Do not check it in.

### Timing feels slightly off at very high BPM

The sequencer uses `Timer.periodic` which relies on Dart's event loop. At BPM values above ~240 the step interval drops below 63 ms and timer jitter may become perceptible. For the intended use case (60–180 BPM) timing is consistent.

---

## Permissions

| Permission | Reason |
|---|---|
| `READ_EXTERNAL_STORAGE` (API ≤ 32) | Load custom audio samples from device storage |
| `READ_MEDIA_AUDIO` (API ≥ 33) | Load custom audio samples from device storage (Android 13+) |
| `RECORD_AUDIO` | Record custom samples via microphone |
