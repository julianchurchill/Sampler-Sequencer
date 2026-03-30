# Sampler-Sequencer Development Guidelines

## Branching Policy

**Never commit directly to `main`.** All changes must go through feature branches and be merged via pull request.

### Workflow

1. Create a feature branch from `main`:
   ```
   git checkout main
   git pull origin main
   git checkout -b feature/your-feature-name
   ```
2. Make your changes and commit to the feature branch.
3. Push the branch and open a pull request targeting `main`.
4. Merge only after the CI build passes (GitHub Actions runs `flutter build apk --release`).

### Branch naming

Use descriptive prefixes:
- `feature/` — new functionality
- `fix/` — bug fixes
- `chore/` — tooling, dependencies, config changes

## Versioning and Changelog

Every pull request that changes user-facing behaviour **must**:

1. **Update `CHANGELOG.md`** — add an entry under a new version heading (or an `[Unreleased]` section if the version hasn't been decided yet). Follow the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format: `### Added`, `### Changed`, `### Fixed`, `### Removed`.

2. **Bump the version in `pubspec.yaml`** (`version: MAJOR.MINOR.PATCH+BUILD`) following [Semantic Versioning](https://semver.org/):
   - `PATCH` — bug fixes, no new features
   - `MINOR` — new backwards-compatible features
   - `MAJOR` — breaking changes
   - `BUILD` — increment by 1 on every release (Android `versionCode`)

Pure housekeeping changes (CI config, docs, tooling) do not require a version bump, but should still note the change in `CHANGELOG.md` if it affects developers.

## Test-Driven Development (TDD)

All new features and bug fixes must follow a TDD workflow:

1. **Write a failing test first** — before writing any implementation code, add a test that describes the expected behaviour and confirm it fails.
2. **Write the minimum code to make it pass** — implement only what is needed to turn the test green.
3. **Refactor** — clean up the implementation while keeping all tests passing.

### Test locations

| What | Where |
|---|---|
| Pure constants | `test/constants_test.dart` |
| `SequencerModel` logic | `test/sequencer_model_logic_test.dart` |
| DSP / WAV utilities | `test/audio_engine_dsp_test.dart` |
| New logical units | `test/<unit_name>_test.dart` |

### Running tests

```
flutter test
```

The pre-commit hook (install with `sh scripts/install-hooks.sh`) runs `flutter test` automatically before every commit and blocks if any test fails. CI also runs `flutter test` before building the APK.

### What to test

- All business logic in `SequencerModel` (BPM, steps, velocity, mute, trim, etc.)
- Pure functions in `lib/audio/dsp_utils.dart`
- Any new pure/injectable logic added elsewhere
- Bug fixes must include a regression test that would have caught the bug

### What not to test

- Platform-dependent audio playback (`AudioEngine` internals requiring a real audio stack)
- Widget rendering (UI layout tests add fragility without proportionate value at this stage)
