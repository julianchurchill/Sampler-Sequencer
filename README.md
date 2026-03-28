# Sampler Sequencer

A hardware-style drum machine and step sequencer for Android, built with Flutter.

![Platform](https://img.shields.io/badge/platform-Android-green)
![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)
![CI](https://github.com/julianchurchill/Sampler-Sequencer/actions/workflows/build.yml/badge.svg?branch=main)

---

## Summary

Sampler Sequencer is a 4-track, 16-step drum machine that runs in landscape orientation on Android. Each track has a synthesised default sound (kick, snare, closed hi-hat, open hi-hat) generated in Dart from PCM maths — no audio files are bundled. You can also load any audio file from device storage per track.

**Key features:**

- 4 tracks: Kick, Snare, HH Closed, HH Open
- 16-step grid per track
- BPM control (40–300 BPM), adjustable with up/down buttons; long-press for ±10 jumps
- Load custom audio samples from device storage per track
- Dark hardware-style UI, landscape-only
- Synthesised drum sounds (kick = pitched sine sweep, snare/hats = filtered noise) — works with no sample files

---

## Architecture

```
lib/
├── main.dart                  # Entry point; forces landscape, sets up Provider
├── constants.dart             # Colours, track names, BPM limits, step counts
├── audio/
│   └── audio_engine.dart      # PCM WAV synthesis + audioplayers playback
├── models/
│   └── sequencer_model.dart   # ChangeNotifier; Timer-based step sequencing
├── screens/
│   └── sequencer_screen.dart  # Root screen (AppBar + tracks + transport)
└── widgets/
    ├── track_row.dart         # One row: label, LOAD/clear buttons, 16 StepButtons
    ├── step_button.dart       # Individual step toggle with playhead highlight
    └── transport_bar.dart     # Play/Stop, BPM display, CLEAR button
```

**State management:** `provider` — `SequencerModel` is a `ChangeNotifier` exposed via `ChangeNotifierProvider`. Each `StepButton` uses `context.select` so only the affected button rebuilds on state change.

**Sequencing:** `Timer.periodic` fires every `60,000,000 / (bpm × 4)` microseconds (one 16th-note step). On each tick the model triggers active tracks via `AudioEngine` then notifies the UI.

**Sound synthesis:** `AudioEngine` generates raw PCM samples in Dart on first play, writes them as 16-bit mono WAV files to the device's temp directory, then plays them back via `AudioPlayer(PlayerMode.lowLatency)` from the `audioplayers` package.

---

## Frameworks & Libraries

| Package | Version | Purpose |
|---|---|---|
| `flutter` | SDK | UI framework |
| `audioplayers` | ^6.0.0 | Low-latency audio playback (Android `SoundPool`) |
| `provider` | ^6.1.1 | Lightweight state management |
| `file_picker` | ^8.0.0 | Load custom audio samples from device storage |
| `path_provider` | ^2.1.0 | Locate temp directory for synthesised WAV files |
| `flutter_lints` | ^3.0.0 | (dev) Lint rules |

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
| `READ_EXTERNAL_STORAGE` (API ≤ 32) | Load custom audio samples |
| `READ_MEDIA_AUDIO` (API ≥ 33) | Load custom audio samples (Android 13+) |
