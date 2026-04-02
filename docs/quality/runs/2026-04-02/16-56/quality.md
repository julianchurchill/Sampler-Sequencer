---
run_date: 2026-04-02
score: 14.099999999999994
grade: F
issue_count: 46
---

# Quality Run - 2026-04-02

## Summary

**Score:** 14.099999999999994/100
**Grade:** F
**Issues Found:** 46

## Issues by Category

| Category | Count |
|----------|-------|
| Security | 7 |
| Reliability | 7 |
| Performance | 5 |
| Maintainability | 10 |
| Testing | 14 |
| Architecture | 2 |
| Documentation | 1 |

## Issue Details

### Architecture

- **major**: Track count is hardcoded as the literal integer 4 in at least seven places inside AudioEngine (_nextSlot, _playerModes, _trackPresetIndex, _trackCustomPath, _trackVolume, _trimStart, _trimEnd, _trimTimers, _trackMuted, _triggerGen initialisation, the init() loop, stopAll() loop) rather than referencing kNumTracks from constants.dart. If the track count is ever changed, AudioEngine will silently diverge from the model.
  - Location: `lib/audio/audio_engine.dart:87`
  - Suggestion: Import kNumTracks from constants.dart and replace every literal 4 with kNumTracks in all List.filled, List.generate, and loop-bound expressions inside AudioEngine. This makes the track count a single source of truth and prevents silent out-of-bounds errors.
- **minor**: AudioExporter contains its own private WAV parser (_readWav, _WavData) that duplicates knowledge already present in dsp_utils.dart (buildWav). The two files now form a pair of read/write halves with no shared contract type. If the WAV format assumptions ever diverge (e.g. block-align calculation, chunk-alignment) they would silently produce incompatible files.
  - Location: `lib/audio/audio_exporter.dart:7`
  - Suggestion: Consider extracting a shared WavCodec or at minimum a WavHeader constant bundle into dsp_utils.dart (or a new wav_utils.dart) so that both the generator and the exporter read from the same structural definitions. At minimum, document in a comment that _readWav is the inverse of buildWav and must stay in sync.

### Maintainability

- **major**: positionStream(int track) accepts a track parameter but completely ignores it, always returning _previewPlayer.onPositionChanged. This is a silent API contract violation — callers reasonably expect that passing track 0 returns a stream scoped to track 0, not a shared stream for whatever track the preview player currently has loaded.
  - Location: `lib/audio/audio_engine.dart:161`
  - Suggestion: Either remove the track parameter (the method is only ever called for the track whose trim editor is open, so the parameter is vacuous) or add a documentation comment at the call site and on the method explicitly stating that a single shared stream is returned regardless of track. The former is cleaner.
- **major**: loadCustomSample2 is a poorly-named method. The trailing digit '2' conveys no meaning; the method exists specifically to load a sample from the SampleLibrary (with a known path and name), whereas loadCustomSample (no suffix) invokes the file picker. The distinction is important but the names make it impossible to tell from a call site which is which.
  - Location: `lib/models/sequencer_model.dart:229`
  - Suggestion: Rename to loadLibrarySample(int track, String path, String name) to distinguish it clearly from loadCustomSample which triggers the file picker. Update all call sites (currently one in track_row.dart).
- **major**: _save() uses fire-and-forget SharedPreferences.getInstance().then() with no error handling. If SharedPreferences.getInstance() rejects (e.g. due to a platform exception), the rejection goes unhandled and will surface as an unhandled Future rejection in debug mode and silently swallow the save in release builds.
  - Location: `lib/models/sequencer_model.dart:139`
  - Suggestion: Add a .catchError or convert to async/await with a try/catch. At minimum log the error: SharedPreferences.getInstance().then((prefs) { ... }).catchError((Object e) { debugPrint('SequencerModel _save error: $e'); });
- **minor**: _SoundPickerSheetState is a long method / god-class concern within track_row.dart. The file is 745 lines and _SoundPickerSheetState alone spans lines 298–537 (~239 lines), combining recording lifecycle management, library name prompting, rename flow, and the entire preset/library/file-browse UI. This violates the single-responsibility principle and makes isolated testing impossible.
  - Location: `lib/widgets/track_row.dart:291`
  - Suggestion: Extract recording state and the record/stop/name-prompt flow into a dedicated _RecordingController or a separate StatefulWidget (e.g. _RecordButton). Consider splitting _SoundPickerSheet into its own file (sound_picker_sheet.dart) to keep track_row.dart focused on layout.
- **minor**: trigger() has a cyclomatic complexity of approximately 14 (1 base + async path branch + trimmed/untrimmed branch + 8 _triggerGen guard checks + mode mismatch branch + end != null check + playDuration > zero check + mutable mode check). While within the 'minor' band, the dense chain of 'if (_triggerGen[track] != gen) return;' guards obscures the actual logic flow.
  - Location: `lib/audio/audio_engine.dart:464`
  - Suggestion: Extract the untrimmed fast-path into a private method _triggerLowLatency(int track, int slot, double volume, int gen) and the trimmed path into _triggerTrimmed(int track, double volume, int gen, Duration start, Duration? end). This reduces trigger() to a dispatcher and makes each path independently readable.
- **minor**: SampleEntry exposes mutable fields (String path, String name) on a public class. The rename() method in SampleLibrary mutates entry.name directly via entry.name = newName. This pattern bypasses encapsulation — external code can mutate entries without going through SampleLibrary, which means notifyListeners() would never be called and the index would not be persisted.
  - Location: `lib/audio/sample_library.dart:8`
  - Suggestion: Make SampleEntry fields final and add a copyWith or update the rename path to replace the entry in _samples rather than mutating it in place. If mutation is intentional, at minimum mark the fields @internal or document the invariant that callers must not mutate entries directly.
- **minor**: Random seed literals (42, 99, 7, 13, 55) are scattered across six drum generator functions with no named constants or comments explaining their significance. While deterministic seeds are intentional (reproducible synthesis), a future developer has no signal that these values are load-bearing and might 'clean them up' by switching to unseeded Random().
  - Location: `lib/audio/dsp_utils.dart:116`
  - Suggestion: Define named constants near the top of dsp_utils.dart: const int _kSnareSeed = 42; const int _kRimShotSeed = 99; etc., and replace the inline literals. Add a one-line comment explaining that fixed seeds ensure bit-identical output across invocations.
- **minor**: SequencerModel.init() is approximately 65 lines long and mixes three concerns: audio engine initialisation, SharedPreferences restoration for steps and BPM, and per-track state restoration. The per-track restoration loop (lines 100–134) is particularly dense, deserving its own private method.
  - Location: `lib/models/sequencer_model.dart:70`
  - Suggestion: Extract _restorePerTrackState(SharedPreferences prefs) as a private helper. This keeps init() as a high-level coordinator and makes the individual restore logic independently testable.
- **minor**: In _togglePreview(), the local variable effectiveEndMs is computed to resolve the null end case, but this same null-resolution logic is duplicated at line 135 in _applyTrim() (endMs < dur.inMilliseconds ? Duration(milliseconds: endMs) : null). The pattern of 'end is null means play to total duration' is repeated in at least three locations across trim_editor_sheet.dart and audio_engine.dart.
  - Location: `lib/widgets/trim_editor_sheet.dart:88`
  - Suggestion: Extract a private helper Duration? _resolvedEnd(Duration duration) inside _TrimEditorSheetState that returns null when endFrac covers the full duration, and use it in both _togglePreview and _applyTrim. This is a 5-10 line duplication — below the major threshold but worth eliminating for clarity.
- **info**: The comment at line 189 inside init() still reads 'Two low-latency SoundPool players per track (8 total).' but the code was updated to use _kSlotsPerTrack = 6 per track (24 total). The stale '8 total' and 'two' references contradict the actual implementation and the correct explanation in the constant's own documentation block.
  - Location: `lib/audio/audio_engine.dart:189`
  - Suggestion: Update the comment to 'Six low-latency SoundPool players per track (24 total)' to match the current _kSlotsPerTrack value. Remove the word 'two' from the ping-pong description in the same block.

### Documentation

- **minor**: The Architecture section's directory tree is stale. It lists only audio_engine.dart under lib/audio/ but omits audio_exporter.dart, audio_recorder.dart, dsp_utils.dart, and sample_library.dart, all of which are substantial modules. It also omits the widgets added since v1.5 (trim_editor_sheet.dart, pad_config_sheet.dart, export_sheet.dart). A developer reading the README to orient themselves will form a misleading picture of the codebase structure.
  - Location: `README.md:28`
  - Suggestion: Update the directory tree to include all current files. Also update the prose description to mention WAV export, sample recording/library, and the trim feature — all of which are significant user-visible capabilities that the Summary section currently omits.

### Reliability

- **major**: Fire-and-forget _save() swallows all SharedPreferences errors silently. The Future returned by SharedPreferences.getInstance().then(...) is never awaited or error-handled; a write failure (storage full, permission revoked) is completely invisible.
  - Location: `lib/models/sequencer_model.dart:139`
  - Suggestion: Attach a .catchError or use async/await with a try/catch to at least log persistence failures, so data-loss scenarios surface in crash reporting or debug logs.
- **major**: _schedulePlayerModeSwitch is fire-and-forget: _rebuildPlayer is unawaited. If the async rebuild races with a trigger() call on the same track, trigger() may use the old (being-disposed) player or the replacement player before its source is loaded, causing silent playback or a platform exception.
  - Location: `lib/audio/audio_engine.dart:313`
  - Suggestion: Track the in-flight rebuild Future per track and have trigger() await it (or guard against the mode mismatch already present) to ensure the player is fully initialised before use. At minimum the existing guard at trigger() line 515 should be documented as the safety net for this race.
- **major**: In the trimmed mediaPlayer path of trigger(), setSource(DeviceFileSource(path)) is called on every trigger. This is the exact pattern the CLAUDE.md invariants explicitly prohibit for the fast path (SoundPoolManager cache growth), yet it is still present in the trimmed path, creating the same lock-contention and timing-jitter risk for trimmed tracks under rapid re-trigger.
  - Location: `lib/audio/audio_engine.dart:523`
  - Suggestion: Cache whether the path has changed since the last setSource call on the primary player and skip setSource when the path is unchanged, matching the low-latency path strategy of pre-loading once and calling resume().
- **minor**: getTrackDuration() calls _previewPlayer.setSource() without stopping or checking whether the preview player is currently playing. If the trim editor is open and actively previewing, calling getTrackDuration() mid-playback will silently interrupt the preview and load a new source, causing the UI playback progress to desync.
  - Location: `lib/audio/audio_engine.dart:347`
  - Suggestion: Stop or check the preview player state before loading a new source for duration probing, or use a separate dedicated player instance for duration probing only.
- **minor**: _loadIndex() calls File(path).exists() sequentially for every index entry, one await per file. For a large library this is an O(n) chain of sequential filesystem stat calls at startup, blocking SampleLibrary.init() and delaying notifyListeners().
  - Location: `lib/audio/sample_library.dart:36`
  - Suggestion: Issue all exists() checks concurrently using Future.wait(), then filter the results. This converts O(n) sequential awaits into a single parallel batch.
- **minor**: _play() calls _audio.init() a second time as a fallback if isReady is false. AudioEngine.init() is not idempotent: it appends to _presetPaths and _players without clearing them first, so a double-init would duplicate all players and preset paths, leaking AudioPlayer instances and creating misaligned player indices.
  - Location: `lib/models/sequencer_model.dart:312`
  - Suggestion: Guard init() against re-entrance (e.g. check _ready or _presetPaths.isNotEmpty at the top of init() and return early), or remove the fallback call in _play() and ensure the startup sequence always completes init() before play is reachable.
- **info**: AudioEngine.init() synthesises all 9 preset WAV files and writes them to the temp directory on every cold start. Temp files are not cleaned up on dispose(). On constrained devices with limited temp storage or repeated cold starts (e.g. after OS temp-dir purges), these 9 files accumulate or must be regenerated, adding startup latency each time.
  - Location: `lib/audio/audio_engine.dart:178`
  - Suggestion: Check whether each preset WAV already exists on disk before regenerating it. Since the presets are deterministic (fixed generators with fixed seeds), the content never changes between runs and the files are safe to reuse across sessions.

### Performance

- **major**: The entire mix buffer is allocated as a Float64List in memory before conversion. At 16 loops × 44100 Hz × 2 channels × 8 bytes/sample this can exceed 90 MB for long sequences (300 BPM / short steps). Both Float64List and the Int16List conversion duplicate the full buffer in memory simultaneously (lines 209-212), so peak RSS is ~2× the buffer size.
  - Location: `lib/audio/audio_exporter.dart:157`
  - Suggestion: Process the mix in chunked passes (e.g. per-loop or per-step block) and write PCM data directly to a byte sink, avoiding holding both float and int representations simultaneously. Alternatively accept the current in-memory approach but document the memory ceiling for the maximum export configuration.
- **major**: WAV PCM samples are serialised into a ByteData buffer one Int16 at a time (O(n) individual setInt16 calls), then added to the file sink. For a 2-minute stereo export at 44100 Hz this is ~10 million method calls in a tight loop on the main isolate, blocking the UI thread for seconds.
  - Location: `lib/audio/audio_exporter.dart:251`
  - Suggestion: Use Int16List.view (or typed list reinterpretation) to write the PCM buffer directly without iterating sample-by-sample. On little-endian hosts (which Android/iOS are), Int16List bytes can be written directly as pcm.buffer.asUint8List() since the WAV spec also uses little-endian.
- **minor**: setTrackVolume() applies the volume change sequentially across all _kSlotsPerTrack players (6 awaits in a loop). Since each await crosses the platform channel boundary, the total latency is 6× the per-call round-trip. This is called from UI slider drag events via SequencerModel, adding unnecessary jank.
  - Location: `lib/audio/audio_engine.dart:170`
  - Suggestion: Fan out the setVolume calls with Future.wait() to issue all platform-channel calls concurrently, reducing total wall-clock time to approximately one round-trip.
- **minor**: _fireAndAdvance() calls notifyListeners() on every sequencer tick to update the playhead highlight. This triggers a rebuild of all 64 StepButton widgets plus the TrackRow and TransportBar subtrees. At 300 BPM (18.75 ms/step) this is 53 rebuilds/second, each involving 64 context.select evaluations.
  - Location: `lib/models/sequencer_model.dart:347`
  - Suggestion: StepButton already uses context.select which limits its rebuild scope correctly. Verify that TransportBar and _TrackLabel use context.select (they do), so the main cost is only the select evaluations. This is acceptable for the current widget count but consider batching or ValueNotifier for the currentStep field if profiling shows frame drops at high BPM.
- **info**: AudioExporter.export() runs entirely on the calling isolate (the Flutter UI isolate). For a 16-loop export at a slow BPM, the mix loop can take several seconds. Although an onProgress callback is provided for UI feedback, the Dart event loop is blocked during the CPU-intensive inner loop, preventing any UI repaints.
  - Location: `lib/audio/audio_exporter.dart:107`
  - Suggestion: Move the export computation into a separate isolate using compute() or Isolate.spawn(). Pass the serialisable parameters (samplePaths, PCM data, BPM, etc.) across the isolate boundary and stream progress updates back via SendPort.

### Security

- **major**: Deserialization of untrusted JSON index file without schema validation. The index.json file is read and cast directly to List<dynamic> with item fields cast to String. A corrupted or tampered index.json (e.g. by another app with shared storage access) could cause type cast exceptions or load arbitrary file paths.
  - Location: `lib/audio/sample_library.dart:39`
  - Suggestion: Add defensive type checks on the decoded JSON structure before casting. Validate that 'path' values are within the expected library directory to prevent path traversal. Wrap individual entry parsing in try-catch so one malformed entry does not break the entire library.
- **minor**: Exception details leaked to user in export error snackbar. The raw exception object is interpolated into the SnackBar text shown to the user, which could expose internal file paths, stack frames, or other implementation details.
  - Location: `lib/widgets/export_sheet.dart:63`
  - Suggestion: Show a generic user-friendly error message instead of interpolating the raw exception. Log the full error via debugPrint for developer diagnostics.
- **minor**: User-supplied file path from file picker is used directly in DeviceFileSource without sanitization. The path passed to setCustomPath originates from FilePicker and is propagated to DeviceFileSource throughout the engine. While FilePicker constrains selection on most platforms, on rooted devices or via intent spoofing the path could reference sensitive files.
  - Location: `lib/audio/audio_engine.dart:248`
  - Suggestion: Validate that the picked file path has an expected audio file extension (.wav, .mp3, .m4a, .ogg, etc.) and optionally copy the file into the app's private directory before loading it, rather than referencing arbitrary external paths.
- **minor**: Custom file path restored from SharedPreferences is used without existence or validity check. A stale or tampered SharedPreferences value for track_custom_path_ is passed directly to AudioEngine.setCustomPathWithName. If the path no longer exists or was replaced with a different file, the app may exhibit unexpected behavior.
  - Location: `lib/models/sequencer_model.dart:103`
  - Suggestion: Before restoring a custom path from preferences, verify the file exists (File(path).existsSync()) and optionally validate the file extension. If the file is missing, fall back to the preset and remove the stale preference entry.
- **minor**: Export output path is constructed from user-controlled timestamp but written without validating the parent directory. While currently the path is built from getTemporaryDirectory, the export method accepts outputPath as an arbitrary string parameter, and any caller could supply a path outside the temp directory.
  - Location: `lib/audio/audio_exporter.dart:256`
  - Suggestion: Add a guard in AudioExporter.export to verify that outputPath resides within the app's temporary or documents directory before writing. This defends against future callers misusing the API.
- **info**: File extension extracted from user-provided temp path via string split without validation. The addRecording method derives the file extension by splitting the path on '.'. An unusual path could result in an unexpected extension or no extension, though the impact is limited to the local library.
  - Location: `lib/audio/sample_library.dart:88`
  - Suggestion: Use a dedicated path utility (e.g. the path package's extension() function) to extract the extension safely, and validate it against an allowlist of expected audio extensions.
- **info**: Several dependencies use caret version ranges (e.g. ^6.0.0) which allow automatic minor/patch upgrades. While convenient, this means builds are not fully reproducible and a compromised transitive dependency could be pulled in on a future resolution. The pubspec.lock file mitigates this for direct builds but not for fresh clones without a committed lock file.
  - Location: `pubspec.yaml:9`
  - Suggestion: Ensure pubspec.lock is committed to version control (verify it is tracked in git). Consider periodically running 'flutter pub upgrade' with review to stay on known-good versions.

### Testing

- **major**: MockAudioEngine is configured in setUp but mock state is never reset between tests. mocktail stubs set with when() persist across tests within the same run unless explicitly cleared, meaning a test that modifies stub behaviour (e.g. changes a thenReturn value mid-test) can silently corrupt subsequent tests.
  - Location: `./test/sequencer_model_logic_test.dart:16`
  - Suggestion: Add a tearDown block that calls reset(audio) after each test, or at minimum verify that no test mutates stub return values. In mocktail, reset() clears both interactions and stubs. Alternatively use resetMocktailState() if supported by the version in use.
- **major**: Shared mutable state at describe scope: wav and pcm are declared at the top of the 'buildWav fade envelope' group and mutated in setUp(). If a future test is added that forgets to call setUp first, or if setUp throws, pcm will retain the previous group's value. The nullable type (Uint8List? wav) with a non-null forced dereference (wav!) in the helper is an additional crash risk.
  - Location: `./test/audio_engine_dsp_test.dart:59`
  - Suggestion: Declare wav and pcm as late inside setUp() and pass them explicitly to helper functions, or initialise them to fresh values unconditionally in setUp() with non-nullable types. This makes the dependency on setUp explicit and eliminates the stale-state window.
- **major**: constants_test.dart imports audio_engine.dart to access kDrumPresets and kDefaultPresetIndices. These values are defined in the AudioEngine source file which imports platform-dependent packages (audioplayers, path_provider). This means the constants test will fail to compile or run on any headless CI host that lacks the platform plugin stubs for audioplayers, breaking coverage for otherwise-pure constant verification.
  - Location: `./test/constants_test.dart:2`
  - Suggestion: Move kDrumPresets and kDefaultPresetIndices out of audio_engine.dart into constants.dart (or a separate drum_presets.dart). The test should import only the constants layer. This also removes the circular layering implied by a test that must pull in the full audio stack to check a numeric constant.
- **major**: AudioExporter has no test coverage. It contains substantial pure logic: WAV parsing (_readWav), timeline computation (stepFrames, outputFrames), stereo mixing loop, peak normalisation, and WAV writing. These are all testable with in-memory byte arrays and do not require a real filesystem or audio stack.
  - Location: `./lib/audio/audio_exporter.dart:1`
  - Suggestion: Add test/audio_exporter_test.dart covering: (1) _readWav rejects non-RIFF, non-WAVE, non-PCM inputs; (2) export mixes a single step at the correct frame offset given a known BPM; (3) normalisation scales output so the peak is 32767 when mix exceeds 1.0; (4) trim start/end offsets the source read window correctly.
- **major**: SampleLibrary has no test coverage. It contains business logic that is independently testable: index loading, migration from legacy files, addRecording path construction, rename, delete, and the JSON serialisation format. The real filesystem calls can be avoided by injecting the directory path or mocking the File/Directory API.
  - Location: `./lib/audio/sample_library.dart:1`
  - Suggestion: Add test/sample_library_test.dart. Use a temporary in-memory directory or a test-scoped tmpdir. Cover: (1) init() creates the library directory; (2) addRecording copies the file and persists the name to index.json; (3) rename() updates the name without renaming the file; (4) delete() removes the file and updates the index; (5) _loadIndex() skips entries whose files no longer exist.
- **major**: Several public SequencerModel methods have no test coverage: toggleMute, clearCustomSample, loadPreset, setTrim, clearTrim, setTrackVolume. These delegate to AudioEngine but also call notifyListeners() and _save(), meaning the listener notification and persistence paths are entirely unverified.
  - Location: `./test/sequencer_model_logic_test.dart:1`
  - Suggestion: Add test groups for each untested method. Since MockAudioEngine is already in place, the cost is low. For example: toggleMute should flip isMuted from false to true and call notifyListeners; setTrim should delegate to audio.setTrim with the supplied arguments; clearTrim should call audio.clearTrim and notify.
- **major**: Four drum generator functions (generateRimShot, generateHiHatOpen, generateClap, generateTom) are present in dsp_utils.dart but have no sample-count or amplitude-range tests. generateKick808 and generateSnare are covered; the remaining four follow identical patterns and are equally testable.
  - Location: `./test/audio_engine_dsp_test.dart:133`
  - Suggestion: Add tests asserting (a) buf.length equals the expected sample count (120 ms, 600 ms, 220 ms, 400 ms respectively at 44100 Hz) and (b) all samples are within [-1.0, 1.0]. Follow the exact pattern already used for generateKick808 and generateSnare in the existing 'drum generators' group.
- **minor**: The 'notifies listeners and updates bpm' test adds a listener but never removes it before the test ends. If SequencerModel.dispose() is not called in a tearDown, the listener callback closure holds a reference into the test frame, which may affect subsequent tests or produce false-positive notification counts when tests share the same model instance across groups.
  - Location: `./test/sequencer_model_logic_test.dart:67`
  - Suggestion: Store the listener in a local variable and remove it in an addTearDown callback: final listener = () => notifyCount++; model.addListener(listener); addTearDown(() => model.removeListener(listener));
- **minor**: Same listener leak as above: the 'notifies listeners and updates step state' test adds a listener without removing it. The same pattern also appears in the setStepVelocity notifies test (line 132) and the clearAllSteps notifies test (line 196).
  - Location: `./test/sequencer_model_logic_test.dart:93`
  - Suggestion: Apply addTearDown(() => model.removeListener(listener)) consistently in all three notification tests, or move listener setup/teardown into a shared helper.
- **minor**: SequencerModel is constructed in setUp() but dispose() is never called in tearDown(). The model holds a Timer (_stepTimer) that could in theory fire after the test ends if a test leaves the model in a playing state. While no current test calls togglePlay(), the absence of tearDown disposal is a latent risk as the test suite grows.
  - Location: `./test/sequencer_model_logic_test.dart:1`
  - Suggestion: Add tearDown(() => model.dispose()); to the top-level setUp/tearDown pair. This also ensures the MockAudioEngine.dispose() stub is exercised, providing an implicit regression guard.
- **minor**: dspEnv is tested for i=0 (full amplitude), i=totalSamples (near-zero), and monotonic decrease over [0, 50). The boundary case where i > totalSamples is not tested — the function is pure math (exp(-decayRate * i / totalSamples)) and would return a value less than the end-of-range value, but confirming this is not asserted. More importantly, the case totalSamples=0 (division by zero) is untested.
  - Location: `./test/audio_engine_dsp_test.dart:111`
  - Suggestion: Add a test for dspEnv with totalSamples=0 to verify it does not throw (or explicitly documents the precondition). Add a test for i > totalSamples to confirm the envelope continues to decay rather than wrapping or resetting.
- **minor**: buildWav is tested with an empty Float64List (0 samples) for header structure. The test for 'output length' uses 100 samples. There is no test for a very short buffer (1 or 2 samples) where kWavFadeSamples is clamped to numSamples/2 — the clamp path at dsp_utils.dart line 25 is exercised but the fade-in/fade-out monotonicity tests use n=2000, which never hits the clamp. The clamp boundary is therefore not covered.
  - Location: `./test/audio_engine_dsp_test.dart:12`
  - Suggestion: Add a test with n = 4 (less than 2 * kWavFadeSamples = 512) to verify that buildWav produces a valid WAV without panicking and that the first and last samples are still zero (fade correctly clamped).
- **info**: constants_test.dart contains only value-equality assertions (expect(k, literal)). These tests provide a useful regression guard against accidental constant changes but offer no coverage of runtime behaviour. The test file name implies pure constant checking, which is fulfilled, but the dependency on audio_engine.dart (see separate finding) means this file's pass/fail is not truly isolated.
  - Location: `./test/constants_test.dart:1`
  - Suggestion: Once kDrumPresets and kDefaultPresetIndices are moved to a constants file (see companion finding), this test file will become a fully isolated unit test with zero platform dependencies. No action needed on the assertions themselves.
- **info**: AppAudioRecorder is a thin wrapper with no tests. As a pure delegate with no logic of its own, the risk of a logic bug is low, but the public contract (hasPermission, start, stop, dispose signatures and the RecordConfig hardcoded values) is not asserted anywhere.
  - Location: `./lib/audio/audio_recorder.dart:1`
  - Suggestion: Either document explicitly that AppAudioRecorder is excluded from testing due to its delegation-only nature, or add a single test that verifies the RecordConfig values (sampleRate: 44100, numChannels: 1, encoder: AudioEncoder.wav) are as expected — these are testable without a real microphone.

## Technical Debt

**Total Estimated Hours:** 65

### Hours by Category

| Category | Hours |
|----------|-------|
| Architecture | 4 |
| Maintainability | 10.25 |
| Documentation | 1 |
| Reliability | 13 |
| Performance | 18.5 |
| Security | 7.5 |
| Testing | 10.75 |

### Hours by Severity

| Severity | Hours |
|----------|-------|
| major | 30.5 |
| minor | 25.75 |
| info | 8.75 |

## Source Breakdown

| Source | Issues |
|--------|--------|
| Analyzers | 0 |
| LLM Investigation | 46 |

## Raw Data

```json
{
  "runId": "2026-04-02T16-56",
  "date": "2026-04-02",
  "score": 14.099999999999994,
  "grade": "F",
  "issueCount": 46,
  "issues": [
    {
      "category": "Architecture",
      "severity": "major",
      "file": "lib/audio/audio_engine.dart",
      "line": 87,
      "message": "Track count is hardcoded as the literal integer 4 in at least seven places inside AudioEngine (_nextSlot, _playerModes, _trackPresetIndex, _trackCustomPath, _trackVolume, _trimStart, _trimEnd, _trimTimers, _trackMuted, _triggerGen initialisation, the init() loop, stopAll() loop) rather than referencing kNumTracks from constants.dart. If the track count is ever changed, AudioEngine will silently diverge from the model.",
      "suggestion": "Import kNumTracks from constants.dart and replace every literal 4 with kNumTracks in all List.filled, List.generate, and loop-bound expressions inside AudioEngine. This makes the track count a single source of truth and prevents silent out-of-bounds errors.",
      "evidence": "final List<int> _nextSlot = List.filled(4, 0);\nfinal List<PlayerMode> _playerModes = List.filled(4, PlayerMode.lowLatency);\nfinal List<int> _trackPresetIndex = List.from(kDefaultPresetIndices);\n// ... and the loop:\nfor (int i = 0; i < 4; i++) {",
      "ruleId": "ARCH-001",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "magic-numbers",
      "scoreImpact": 3
    },
    {
      "category": "Maintainability",
      "severity": "major",
      "file": "lib/audio/audio_engine.dart",
      "line": 161,
      "message": "positionStream(int track) accepts a track parameter but completely ignores it, always returning _previewPlayer.onPositionChanged. This is a silent API contract violation — callers reasonably expect that passing track 0 returns a stream scoped to track 0, not a shared stream for whatever track the preview player currently has loaded.",
      "suggestion": "Either remove the track parameter (the method is only ever called for the track whose trim editor is open, so the parameter is vacuous) or add a documentation comment at the call site and on the method explicitly stating that a single shared stream is returned regardless of track. The former is cleaner.",
      "evidence": "Stream<Duration> positionStream(int track) =>\n    _previewPlayer.onPositionChanged;",
      "ruleId": "MAINT-001",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "naming",
      "scoreImpact": 2.5
    },
    {
      "category": "Maintainability",
      "severity": "major",
      "file": "lib/models/sequencer_model.dart",
      "line": 229,
      "message": "loadCustomSample2 is a poorly-named method. The trailing digit '2' conveys no meaning; the method exists specifically to load a sample from the SampleLibrary (with a known path and name), whereas loadCustomSample (no suffix) invokes the file picker. The distinction is important but the names make it impossible to tell from a call site which is which.",
      "suggestion": "Rename to loadLibrarySample(int track, String path, String name) to distinguish it clearly from loadCustomSample which triggers the file picker. Update all call sites (currently one in track_row.dart).",
      "evidence": "/// Load a library sample with a known [path] and display [name].\nvoid loadCustomSample2(int track, String path, String name) {\n  _audio.setCustomPathWithName(track, path, name);\n  notifyListeners();\n  _save();\n}",
      "ruleId": "MAINT-002",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "naming",
      "scoreImpact": 2
    },
    {
      "category": "Maintainability",
      "severity": "major",
      "file": "lib/models/sequencer_model.dart",
      "line": 139,
      "message": "_save() uses fire-and-forget SharedPreferences.getInstance().then() with no error handling. If SharedPreferences.getInstance() rejects (e.g. due to a platform exception), the rejection goes unhandled and will surface as an unhandled Future rejection in debug mode and silently swallow the save in release builds.",
      "suggestion": "Add a .catchError or convert to async/await with a try/catch. At minimum log the error: SharedPreferences.getInstance().then((prefs) { ... }).catchError((Object e) { debugPrint('SequencerModel _save error: $e'); });",
      "evidence": "void _save() {\n  SharedPreferences.getInstance().then((prefs) {\n    // Steps\n    final stepsStr = _steps\n        .map((track) => track.map((s) => s ? '1' : '0').join())\n        .join('|');",
      "ruleId": "MAINT-003",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "complexity",
      "scoreImpact": 2
    },
    {
      "category": "Maintainability",
      "severity": "minor",
      "file": "lib/widgets/track_row.dart",
      "line": 291,
      "message": "_SoundPickerSheetState is a long method / god-class concern within track_row.dart. The file is 745 lines and _SoundPickerSheetState alone spans lines 298–537 (~239 lines), combining recording lifecycle management, library name prompting, rename flow, and the entire preset/library/file-browse UI. This violates the single-responsibility principle and makes isolated testing impossible.",
      "suggestion": "Extract recording state and the record/stop/name-prompt flow into a dedicated _RecordingController or a separate StatefulWidget (e.g. _RecordButton). Consider splitting _SoundPickerSheet into its own file (sound_picker_sheet.dart) to keep track_row.dart focused on layout.",
      "evidence": "class _SoundPickerSheetState extends State<_SoundPickerSheet> {\n  _RecordState _recordState = _RecordState.idle;\n  final _recorder = AppAudioRecorder();\n  String? _tempPath;\n  final _nameController = TextEditingController();\n  // ... recording, naming, renaming, library, file-browse all in one class",
      "ruleId": "MAINT-004",
      "source": "llm",
      "effort": "medium",
      "effortHours": 3,
      "theme": "god-class",
      "scoreImpact": 2.5
    },
    {
      "category": "Maintainability",
      "severity": "minor",
      "file": "lib/audio/audio_engine.dart",
      "line": 464,
      "message": "trigger() has a cyclomatic complexity of approximately 14 (1 base + async path branch + trimmed/untrimmed branch + 8 _triggerGen guard checks + mode mismatch branch + end != null check + playDuration > zero check + mutable mode check). While within the 'minor' band, the dense chain of 'if (_triggerGen[track] != gen) return;' guards obscures the actual logic flow.",
      "suggestion": "Extract the untrimmed fast-path into a private method _triggerLowLatency(int track, int slot, double volume, int gen) and the trimmed path into _triggerTrimmed(int track, double volume, int gen, Duration start, Duration? end). This reduces trigger() to a dispatcher and makes each path independently readable.",
      "evidence": "Future<void> trigger(int track, {double velocity = 1.0}) async {\n  if (!_ready) return;\n  if (_trackMuted[track]) return;\n  final gen = ++_triggerGen[track];\n  // ... 80 lines combining fast-path and trimmed-path with interleaved gen guards",
      "ruleId": "MAINT-005",
      "source": "llm",
      "effort": "medium",
      "effortHours": 2,
      "theme": "complexity",
      "scoreImpact": 1.5
    },
    {
      "category": "Maintainability",
      "severity": "minor",
      "file": "lib/audio/sample_library.dart",
      "line": 8,
      "message": "SampleEntry exposes mutable fields (String path, String name) on a public class. The rename() method in SampleLibrary mutates entry.name directly via entry.name = newName. This pattern bypasses encapsulation — external code can mutate entries without going through SampleLibrary, which means notifyListeners() would never be called and the index would not be persisted.",
      "suggestion": "Make SampleEntry fields final and add a copyWith or update the rename path to replace the entry in _samples rather than mutating it in place. If mutation is intentional, at minimum mark the fields @internal or document the invariant that callers must not mutate entries directly.",
      "evidence": "class SampleEntry {\n  SampleEntry({required this.path, required this.name});\n  String path;\n  String name;\n}",
      "ruleId": "MAINT-006",
      "source": "llm",
      "effort": "small",
      "effortHours": 1.5,
      "theme": "type-safety",
      "scoreImpact": 1.5
    },
    {
      "category": "Maintainability",
      "severity": "minor",
      "file": "lib/audio/dsp_utils.dart",
      "line": 116,
      "message": "Random seed literals (42, 99, 7, 13, 55) are scattered across six drum generator functions with no named constants or comments explaining their significance. While deterministic seeds are intentional (reproducible synthesis), a future developer has no signal that these values are load-bearing and might 'clean them up' by switching to unseeded Random().",
      "suggestion": "Define named constants near the top of dsp_utils.dart: const int _kSnareSeed = 42; const int _kRimShotSeed = 99; etc., and replace the inline literals. Add a one-line comment explaining that fixed seeds ensure bit-identical output across invocations.",
      "evidence": "final rng = math.Random(42); // generateSnare\nfinal rng = math.Random(99); // generateRimShot\nfinal rng = math.Random(7);  // generateHiHatClosed\nfinal rng = math.Random(13); // generateHiHatOpen\nfinal rng = math.Random(55); // generateClap",
      "ruleId": "MAINT-007",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "magic-numbers",
      "scoreImpact": 1
    },
    {
      "category": "Maintainability",
      "severity": "minor",
      "file": "lib/models/sequencer_model.dart",
      "line": 70,
      "message": "SequencerModel.init() is approximately 65 lines long and mixes three concerns: audio engine initialisation, SharedPreferences restoration for steps and BPM, and per-track state restoration. The per-track restoration loop (lines 100–134) is particularly dense, deserving its own private method.",
      "suggestion": "Extract _restorePerTrackState(SharedPreferences prefs) as a private helper. This keeps init() as a high-level coordinator and makes the individual restore logic independently testable.",
      "evidence": "Future<void> init() async {\n  _isLoading = true;\n  notifyListeners();\n  try {\n    await _audio.init();\n  } finally {\n    _isLoading = false;\n  }\n  final prefs = await SharedPreferences.getInstance();\n  // steps, BPM, then a 35-line per-track loop all inline",
      "ruleId": "MAINT-008",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "long-method",
      "scoreImpact": 1
    },
    {
      "category": "Architecture",
      "severity": "minor",
      "file": "lib/audio/audio_exporter.dart",
      "line": 7,
      "message": "AudioExporter contains its own private WAV parser (_readWav, _WavData) that duplicates knowledge already present in dsp_utils.dart (buildWav). The two files now form a pair of read/write halves with no shared contract type. If the WAV format assumptions ever diverge (e.g. block-align calculation, chunk-alignment) they would silently produce incompatible files.",
      "suggestion": "Consider extracting a shared WavCodec or at minimum a WavHeader constant bundle into dsp_utils.dart (or a new wav_utils.dart) so that both the generator and the exporter read from the same structural definitions. At minimum, document in a comment that _readWav is the inverse of buildWav and must stay in sync.",
      "evidence": "// In audio_exporter.dart — private parser:\nclass _WavData { ... }\nstatic Future<_WavData?> _readWav(String path) async { ... }\n\n// In dsp_utils.dart — writer:\nUint8List buildWav(Float64List samples, int sampleRate) { ... }",
      "ruleId": "ARCH-002",
      "source": "llm",
      "effort": "medium",
      "effortHours": 3,
      "theme": "duplication",
      "scoreImpact": 2
    },
    {
      "category": "Maintainability",
      "severity": "minor",
      "file": "lib/widgets/trim_editor_sheet.dart",
      "line": 88,
      "message": "In _togglePreview(), the local variable effectiveEndMs is computed to resolve the null end case, but this same null-resolution logic is duplicated at line 135 in _applyTrim() (endMs < dur.inMilliseconds ? Duration(milliseconds: endMs) : null). The pattern of 'end is null means play to total duration' is repeated in at least three locations across trim_editor_sheet.dart and audio_engine.dart.",
      "suggestion": "Extract a private helper Duration? _resolvedEnd(Duration duration) inside _TrimEditorSheetState that returns null when endFrac covers the full duration, and use it in both _togglePreview and _applyTrim. This is a 5-10 line duplication — below the major threshold but worth eliminating for clarity.",
      "evidence": "// _togglePreview (line ~95):\nfinal end = endMs < dur.inMilliseconds ? Duration(milliseconds: endMs) : null;\n// _applyTrim (line ~135):\nendMs < dur.inMilliseconds ? Duration(milliseconds: endMs) : null,",
      "ruleId": "MAINT-009",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "duplication",
      "scoreImpact": 0.5
    },
    {
      "category": "Documentation",
      "severity": "minor",
      "file": "README.md",
      "line": 28,
      "message": "The Architecture section's directory tree is stale. It lists only audio_engine.dart under lib/audio/ but omits audio_exporter.dart, audio_recorder.dart, dsp_utils.dart, and sample_library.dart, all of which are substantial modules. It also omits the widgets added since v1.5 (trim_editor_sheet.dart, pad_config_sheet.dart, export_sheet.dart). A developer reading the README to orient themselves will form a misleading picture of the codebase structure.",
      "suggestion": "Update the directory tree to include all current files. Also update the prose description to mention WAV export, sample recording/library, and the trim feature — all of which are significant user-visible capabilities that the Summary section currently omits.",
      "evidence": "lib/\n├── audio/\n│   └── audio_engine.dart      # PCM WAV synthesis + audioplayers playback\n# Missing: audio_exporter.dart, audio_recorder.dart, dsp_utils.dart, sample_library.dart\n└── widgets/\n    ├── track_row.dart\n    ├── step_button.dart\n    └── transport_bar.dart\n    # Missing: trim_editor_sheet.dart, pad_config_sheet.dart, export_sheet.dart",
      "ruleId": "DOC-001",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "stale-docs",
      "scoreImpact": 1
    },
    {
      "category": "Maintainability",
      "severity": "info",
      "file": "lib/audio/audio_engine.dart",
      "line": 189,
      "message": "The comment at line 189 inside init() still reads 'Two low-latency SoundPool players per track (8 total).' but the code was updated to use _kSlotsPerTrack = 6 per track (24 total). The stale '8 total' and 'two' references contradict the actual implementation and the correct explanation in the constant's own documentation block.",
      "suggestion": "Update the comment to 'Six low-latency SoundPool players per track (24 total)' to match the current _kSlotsPerTrack value. Remove the word 'two' from the ping-pong description in the same block.",
      "evidence": "// Two low-latency SoundPool players per track (8 total).\n//\n// Ping-pong retrigger: on each trigger the engine uses the NEXT slot and\n// stops only that slot's previous stream (from 2+ triggers ago, amplitude\n// well into decay). The slot used for the IMMEDIATELY preceding trigger is",
      "ruleId": "MAINT-010",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.25,
      "theme": "stale-docs",
      "scoreImpact": 0.5
    },
    {
      "category": "Reliability",
      "severity": "major",
      "file": "lib/models/sequencer_model.dart",
      "line": 139,
      "message": "Fire-and-forget _save() swallows all SharedPreferences errors silently. The Future returned by SharedPreferences.getInstance().then(...) is never awaited or error-handled; a write failure (storage full, permission revoked) is completely invisible.",
      "suggestion": "Attach a .catchError or use async/await with a try/catch to at least log persistence failures, so data-loss scenarios surface in crash reporting or debug logs.",
      "evidence": "void _save() {\n  SharedPreferences.getInstance().then((prefs) {\n    // Steps\n    final stepsStr = _steps\n        .map((track) => track.map((s) => s ? '1' : '0').join())\n        .join('|');\n    prefs.setString(_kPrefsSteps, stepsStr);",
      "ruleId": "REL-001",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "resource-cleanup",
      "scoreImpact": 6
    },
    {
      "category": "Reliability",
      "severity": "major",
      "file": "lib/audio/audio_engine.dart",
      "line": 313,
      "message": "_schedulePlayerModeSwitch is fire-and-forget: _rebuildPlayer is unawaited. If the async rebuild races with a trigger() call on the same track, trigger() may use the old (being-disposed) player or the replacement player before its source is loaded, causing silent playback or a platform exception.",
      "suggestion": "Track the in-flight rebuild Future per track and have trigger() await it (or guard against the mode mismatch already present) to ensure the player is fully initialised before use. At minimum the existing guard at trigger() line 515 should be documented as the safety net for this race.",
      "evidence": "void _schedulePlayerModeSwitch(int track, PlayerMode mode) {\n  if (!_ready) return;\n  if (_playerModes[track] == mode) return;\n  _playerModes[track] = mode;\n  _rebuildPlayer(track, mode).catchError((Object e) {\n    debugPrint('AudioEngine mode switch error on track $track: $e');\n  });",
      "ruleId": "REL-002",
      "source": "llm",
      "effort": "medium",
      "effortHours": 3,
      "theme": "blocking-io",
      "scoreImpact": 7
    },
    {
      "category": "Reliability",
      "severity": "major",
      "file": "lib/audio/audio_engine.dart",
      "line": 523,
      "message": "In the trimmed mediaPlayer path of trigger(), setSource(DeviceFileSource(path)) is called on every trigger. This is the exact pattern the CLAUDE.md invariants explicitly prohibit for the fast path (SoundPoolManager cache growth), yet it is still present in the trimmed path, creating the same lock-contention and timing-jitter risk for trimmed tracks under rapid re-trigger.",
      "suggestion": "Cache whether the path has changed since the last setSource call on the primary player and skip setSource when the path is unchanged, matching the low-latency path strategy of pre-loading once and calling resume().",
      "evidence": "await player.setVolume(0.0);\nif (_triggerGen[track] != gen) return;\nawait player.stop();\nif (_triggerGen[track] != gen) return;\nawait player.setSource(DeviceFileSource(path));\nif (_triggerGen[track] != gen) return;",
      "ruleId": "PERF-001",
      "source": "llm",
      "effort": "medium",
      "effortHours": 4,
      "theme": "blocking-io",
      "scoreImpact": 8
    },
    {
      "category": "Performance",
      "severity": "major",
      "file": "lib/audio/audio_exporter.dart",
      "line": 157,
      "message": "The entire mix buffer is allocated as a Float64List in memory before conversion. At 16 loops × 44100 Hz × 2 channels × 8 bytes/sample this can exceed 90 MB for long sequences (300 BPM / short steps). Both Float64List and the Int16List conversion duplicate the full buffer in memory simultaneously (lines 209-212), so peak RSS is ~2× the buffer size.",
      "suggestion": "Process the mix in chunked passes (e.g. per-loop or per-step block) and write PCM data directly to a byte sink, avoiding holding both float and int representations simultaneously. Alternatively accept the current in-memory approach but document the memory ceiling for the maximum export configuration.",
      "evidence": "// ── Mix into a float buffer ─────────────────────────────────────────────\nfinal buf = Float64List(outputFrames * _kNumChannels);\n...\nfinal pcm = Int16List(outputFrames * _kNumChannels);\nfor (int i = 0; i < pcm.length; i++) {\n  pcm[i] = (buf[i] * scale * 32767).round().clamp(-32768, 32767);",
      "ruleId": "PERF-002",
      "source": "llm",
      "effort": "large",
      "effortHours": 8,
      "theme": "memory-leak",
      "scoreImpact": 7
    },
    {
      "category": "Performance",
      "severity": "major",
      "file": "lib/audio/audio_exporter.dart",
      "line": 251,
      "message": "WAV PCM samples are serialised into a ByteData buffer one Int16 at a time (O(n) individual setInt16 calls), then added to the file sink. For a 2-minute stereo export at 44100 Hz this is ~10 million method calls in a tight loop on the main isolate, blocking the UI thread for seconds.",
      "suggestion": "Use Int16List.view (or typed list reinterpretation) to write the PCM buffer directly without iterating sample-by-sample. On little-endian hosts (which Android/iOS are), Int16List bytes can be written directly as pcm.buffer.asUint8List() since the WAV spec also uses little-endian.",
      "evidence": "final pcmBytes = ByteData(dataSize);\nfor (int i = 0; i < pcm.length; i++) {\n  pcmBytes.setInt16(i * 2, pcm[i], Endian.little);\n}\n\nfinal file = File(path);\nfinal sink = file.openWrite();\nsink.add(hdr.buffer.asUint8List());\nsink.add(pcmBytes.buffer.asUint8List());",
      "ruleId": "PERF-003",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "algorithm",
      "scoreImpact": 8
    },
    {
      "category": "Reliability",
      "severity": "minor",
      "file": "lib/audio/audio_engine.dart",
      "line": 347,
      "message": "getTrackDuration() calls _previewPlayer.setSource() without stopping or checking whether the preview player is currently playing. If the trim editor is open and actively previewing, calling getTrackDuration() mid-playback will silently interrupt the preview and load a new source, causing the UI playback progress to desync.",
      "suggestion": "Stop or check the preview player state before loading a new source for duration probing, or use a separate dedicated player instance for duration probing only.",
      "evidence": "Future<Duration?> getTrackDuration(int track) async {\n  if (!_ready) return null;\n  final path = samplePath(track);\n  try {\n    await _previewPlayer.setSource(DeviceFileSource(path));\n    return await _previewPlayer.getDuration();",
      "ruleId": "REL-003",
      "source": "llm",
      "effort": "small",
      "effortHours": 2,
      "theme": "resource-cleanup",
      "scoreImpact": 4
    },
    {
      "category": "Reliability",
      "severity": "minor",
      "file": "lib/audio/sample_library.dart",
      "line": 36,
      "message": "_loadIndex() calls File(path).exists() sequentially for every index entry, one await per file. For a large library this is an O(n) chain of sequential filesystem stat calls at startup, blocking SampleLibrary.init() and delaying notifyListeners().",
      "suggestion": "Issue all exists() checks concurrently using Future.wait(), then filter the results. This converts O(n) sequential awaits into a single parallel batch.",
      "evidence": "for (final item in data) {\n  final path = item['path'] as String;\n  final name = item['name'] as String;\n  if (await File(path).exists()) {\n    _samples.add(SampleEntry(path: path, name: name));\n  }\n}",
      "ruleId": "PERF-004",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "blocking-io",
      "scoreImpact": 3
    },
    {
      "category": "Performance",
      "severity": "minor",
      "file": "lib/audio/audio_engine.dart",
      "line": 170,
      "message": "setTrackVolume() applies the volume change sequentially across all _kSlotsPerTrack players (6 awaits in a loop). Since each await crosses the platform channel boundary, the total latency is 6× the per-call round-trip. This is called from UI slider drag events via SequencerModel, adding unnecessary jank.",
      "suggestion": "Fan out the setVolume calls with Future.wait() to issue all platform-channel calls concurrently, reducing total wall-clock time to approximately one round-trip.",
      "evidence": "Future<void> setTrackVolume(int track, double volume) async {\n  _trackVolume[track] = volume.clamp(0.0, 1.0);\n  // Apply to both slots so whichever is currently playing reflects the change.\n  for (int s = 0; s < _kSlotsPerTrack; s++) {\n    await _players[track * _kSlotsPerTrack + s].setVolume(_trackVolume[track]);\n  }",
      "ruleId": "PERF-005",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "blocking-io",
      "scoreImpact": 4
    },
    {
      "category": "Reliability",
      "severity": "minor",
      "file": "lib/models/sequencer_model.dart",
      "line": 312,
      "message": "_play() calls _audio.init() a second time as a fallback if isReady is false. AudioEngine.init() is not idempotent: it appends to _presetPaths and _players without clearing them first, so a double-init would duplicate all players and preset paths, leaking AudioPlayer instances and creating misaligned player indices.",
      "suggestion": "Guard init() against re-entrance (e.g. check _ready or _presetPaths.isNotEmpty at the top of init() and return early), or remove the fallback call in _play() and ensure the startup sequence always completes init() before play is reachable.",
      "evidence": "Future<void> _play() async {\n  try {\n    if (!_audio.isReady) {\n      // Fallback in case init() hasn't completed yet.\n      _isLoading = true;\n      notifyListeners();\n      await _audio.init();\n      _isLoading = false;",
      "ruleId": "REL-004",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "resource-cleanup",
      "scoreImpact": 5
    },
    {
      "category": "Performance",
      "severity": "minor",
      "file": "lib/models/sequencer_model.dart",
      "line": 347,
      "message": "_fireAndAdvance() calls notifyListeners() on every sequencer tick to update the playhead highlight. This triggers a rebuild of all 64 StepButton widgets plus the TrackRow and TransportBar subtrees. At 300 BPM (18.75 ms/step) this is 53 rebuilds/second, each involving 64 context.select evaluations.",
      "suggestion": "StepButton already uses context.select which limits its rebuild scope correctly. Verify that TransportBar and _TrackLabel use context.select (they do), so the main cost is only the select evaluations. This is acceptable for the current widget count but consider batching or ValueNotifier for the currentStep field if profiling shows frame drops at high BPM.",
      "evidence": "void _fireAndAdvance() {\n  for (int t = 0; t < kNumTracks; t++) {\n    if (_steps[t][_currentStep]) {\n      _audio.trigger(t, velocity: _stepVelocity[t][_currentStep]);\n    }\n  }\n  notifyListeners();\n  _currentStep = (_currentStep + 1) % kNumSteps;",
      "ruleId": "PERF-006",
      "source": "llm",
      "effort": "medium",
      "effortHours": 3,
      "theme": "rendering",
      "scoreImpact": 3
    },
    {
      "category": "Performance",
      "severity": "info",
      "file": "lib/audio/audio_exporter.dart",
      "line": 107,
      "message": "AudioExporter.export() runs entirely on the calling isolate (the Flutter UI isolate). For a 16-loop export at a slow BPM, the mix loop can take several seconds. Although an onProgress callback is provided for UI feedback, the Dart event loop is blocked during the CPU-intensive inner loop, preventing any UI repaints.",
      "suggestion": "Move the export computation into a separate isolate using compute() or Isolate.spawn(). Pass the serialisable parameters (samplePaths, PCM data, BPM, etc.) across the isolate boundary and stream progress updates back via SendPort.",
      "evidence": "static Future<void> export({\n  required List<String> samplePaths,\n  ...\n  void Function(double)? onProgress,\n}) async {\n  ...\n  for (int t = 0; t < numTracks; t++) {\n    ...\n    for (int step = 0; step < totalSteps; step++) {",
      "ruleId": "PERF-007",
      "source": "llm",
      "effort": "large",
      "effortHours": 6,
      "theme": "blocking-io",
      "scoreImpact": 3
    },
    {
      "category": "Reliability",
      "severity": "info",
      "file": "lib/audio/audio_engine.dart",
      "line": 178,
      "message": "AudioEngine.init() synthesises all 9 preset WAV files and writes them to the temp directory on every cold start. Temp files are not cleaned up on dispose(). On constrained devices with limited temp storage or repeated cold starts (e.g. after OS temp-dir purges), these 9 files accumulate or must be regenerated, adding startup latency each time.",
      "suggestion": "Check whether each preset WAV already exists on disk before regenerating it. Since the presets are deterministic (fixed generators with fixed seeds), the content never changes between runs and the files are safe to reuse across sessions.",
      "evidence": "Future<void> init() async {\n  final tmpDir = await getTemporaryDirectory();\n\n  // Synthesise all presets to temp WAV files.\n  for (int i = 0; i < kDrumPresets.length; i++) {\n    final wavData = buildWav(kDrumPresets[i].generator(_kSampleRate), _kSampleRate);\n    final path = '${tmpDir.path}/preset_$i.wav';\n    await File(path).writeAsBytes(wavData);",
      "ruleId": "REL-005",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "resource-cleanup",
      "scoreImpact": 2
    },
    {
      "category": "Security",
      "severity": "major",
      "file": "lib/audio/sample_library.dart",
      "line": 39,
      "message": "Deserialization of untrusted JSON index file without schema validation. The index.json file is read and cast directly to List<dynamic> with item fields cast to String. A corrupted or tampered index.json (e.g. by another app with shared storage access) could cause type cast exceptions or load arbitrary file paths.",
      "suggestion": "Add defensive type checks on the decoded JSON structure before casting. Validate that 'path' values are within the expected library directory to prevent path traversal. Wrap individual entry parsing in try-catch so one malformed entry does not break the entire library.",
      "evidence": "final data = jsonDecode(await _indexFile!.readAsString()) as List<dynamic>;\nfor (final item in data) {\n  final path = item['path'] as String;\n  final name = item['name'] as String;",
      "ruleId": "SEC-001",
      "source": "llm",
      "effort": "small",
      "effortHours": 2,
      "theme": "input-validation",
      "scoreImpact": 6,
      "references": [
        "CWE-502",
        "CWE-22"
      ]
    },
    {
      "category": "Security",
      "severity": "minor",
      "file": "lib/widgets/export_sheet.dart",
      "line": 63,
      "message": "Exception details leaked to user in export error snackbar. The raw exception object is interpolated into the SnackBar text shown to the user, which could expose internal file paths, stack frames, or other implementation details.",
      "suggestion": "Show a generic user-friendly error message instead of interpolating the raw exception. Log the full error via debugPrint for developer diagnostics.",
      "evidence": "ScaffoldMessenger.of(context).showSnackBar(\n  SnackBar(content: Text('Export failed: $e')),\n);",
      "ruleId": "SEC-002",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "data-exposure",
      "scoreImpact": 2,
      "references": [
        "CWE-200",
        "CWE-209"
      ]
    },
    {
      "category": "Security",
      "severity": "minor",
      "file": "lib/audio/audio_engine.dart",
      "line": 248,
      "message": "User-supplied file path from file picker is used directly in DeviceFileSource without sanitization. The path passed to setCustomPath originates from FilePicker and is propagated to DeviceFileSource throughout the engine. While FilePicker constrains selection on most platforms, on rooted devices or via intent spoofing the path could reference sensitive files.",
      "suggestion": "Validate that the picked file path has an expected audio file extension (.wav, .mp3, .m4a, .ogg, etc.) and optionally copy the file into the app's private directory before loading it, rather than referencing arbitrary external paths.",
      "evidence": "void setCustomPath(int track, String path) {\n  _trackCustomPath[track] = path;\n  ...\n  _scheduleSourceReload(track);\n}",
      "ruleId": "SEC-003",
      "source": "llm",
      "effort": "small",
      "effortHours": 2,
      "theme": "input-validation",
      "scoreImpact": 3,
      "references": [
        "CWE-22",
        "CWE-20"
      ]
    },
    {
      "category": "Security",
      "severity": "minor",
      "file": "lib/models/sequencer_model.dart",
      "line": 103,
      "message": "Custom file path restored from SharedPreferences is used without existence or validity check. A stale or tampered SharedPreferences value for track_custom_path_ is passed directly to AudioEngine.setCustomPathWithName. If the path no longer exists or was replaced with a different file, the app may exhibit unexpected behavior.",
      "suggestion": "Before restoring a custom path from preferences, verify the file exists (File(path).existsSync()) and optionally validate the file extension. If the file is missing, fall back to the preset and remove the stale preference entry.",
      "evidence": "final customPath = prefs.getString('$_kPrefsTrackCustomPath$t');\nif (customPath != null) {\n  final customName = prefs.getString('$_kPrefsTrackCustomName$t') ?? customPath.split('/').last;\n  _audio.setCustomPathWithName(t, customPath, customName);\n}",
      "ruleId": "SEC-004",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "input-validation",
      "scoreImpact": 2,
      "references": [
        "CWE-20",
        "CWE-284"
      ]
    },
    {
      "category": "Security",
      "severity": "minor",
      "file": "lib/audio/audio_exporter.dart",
      "line": 256,
      "message": "Export output path is constructed from user-controlled timestamp but written without validating the parent directory. While currently the path is built from getTemporaryDirectory, the export method accepts outputPath as an arbitrary string parameter, and any caller could supply a path outside the temp directory.",
      "suggestion": "Add a guard in AudioExporter.export to verify that outputPath resides within the app's temporary or documents directory before writing. This defends against future callers misusing the API.",
      "evidence": "final file = File(path);\nfinal sink = file.openWrite();\nsink.add(hdr.buffer.asUint8List());\nsink.add(pcmBytes.buffer.asUint8List());\nawait sink.close();",
      "ruleId": "SEC-005",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "input-validation",
      "scoreImpact": 2,
      "references": [
        "CWE-22"
      ]
    },
    {
      "category": "Security",
      "severity": "info",
      "file": "lib/audio/sample_library.dart",
      "line": 88,
      "message": "File extension extracted from user-provided temp path via string split without validation. The addRecording method derives the file extension by splitting the path on '.'. An unusual path could result in an unexpected extension or no extension, though the impact is limited to the local library.",
      "suggestion": "Use a dedicated path utility (e.g. the path package's extension() function) to extract the extension safely, and validate it against an allowlist of expected audio extensions.",
      "evidence": "final ext = tempPath.contains('.') ? tempPath.split('.').last : 'm4a';",
      "ruleId": "SEC-006",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "input-validation",
      "scoreImpact": 1,
      "references": [
        "CWE-20"
      ]
    },
    {
      "category": "Security",
      "severity": "info",
      "file": "pubspec.yaml",
      "line": 9,
      "message": "Several dependencies use caret version ranges (e.g. ^6.0.0) which allow automatic minor/patch upgrades. While convenient, this means builds are not fully reproducible and a compromised transitive dependency could be pulled in on a future resolution. The pubspec.lock file mitigates this for direct builds but not for fresh clones without a committed lock file.",
      "suggestion": "Ensure pubspec.lock is committed to version control (verify it is tracked in git). Consider periodically running 'flutter pub upgrade' with review to stay on known-good versions.",
      "evidence": "audioplayers: ^6.0.0\nfile_picker: ^8.0.0\npackage_info_plus: ^8.0.0\nprovider: ^6.1.1\npath_provider: ^2.1.0",
      "ruleId": "SEC-007",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "dependency-risk",
      "scoreImpact": 1,
      "references": [
        "CWE-1104"
      ]
    },
    {
      "category": "Testing",
      "severity": "major",
      "file": "./test/sequencer_model_logic_test.dart",
      "line": 16,
      "message": "MockAudioEngine is configured in setUp but mock state is never reset between tests. mocktail stubs set with when() persist across tests within the same run unless explicitly cleared, meaning a test that modifies stub behaviour (e.g. changes a thenReturn value mid-test) can silently corrupt subsequent tests.",
      "suggestion": "Add a tearDown block that calls reset(audio) after each test, or at minimum verify that no test mutates stub return values. In mocktail, reset() clears both interactions and stubs. Alternatively use resetMocktailState() if supported by the version in use.",
      "evidence": "setUp(() {\n  SharedPreferences.setMockInitialValues({});\n  audio = MockAudioEngine();\n  when(() => audio.isReady).thenReturn(false);\n  // ... more stubs, no matching tearDown/reset\n  model = SequencerModel(audio: audio);\n});",
      "ruleId": "TEST-missing-mock-cleanup",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.25,
      "theme": "test-isolation",
      "scoreImpact": 3.5
    },
    {
      "category": "Testing",
      "severity": "major",
      "file": "./test/audio_engine_dsp_test.dart",
      "line": 59,
      "message": "Shared mutable state at describe scope: wav and pcm are declared at the top of the 'buildWav fade envelope' group and mutated in setUp(). If a future test is added that forgets to call setUp first, or if setUp throws, pcm will retain the previous group's value. The nullable type (Uint8List? wav) with a non-null forced dereference (wav!) in the helper is an additional crash risk.",
      "suggestion": "Declare wav and pcm as late inside setUp() and pass them explicitly to helper functions, or initialise them to fresh values unconditionally in setUp() with non-nullable types. This makes the dependency on setUp explicit and eliminates the stale-state window.",
      "evidence": "Uint8List? wav;\nlate ByteData pcm;\n\nsetUp(() {\n  wav = buildWav(constantSamples, _kSampleRate);\n  pcm = ByteData.sublistView(wav!);\n});\n\nint readPcm(int sampleIndex) =>\n    pcm.getInt16(44 + sampleIndex * 2, Endian.little);",
      "ruleId": "TEST-flaky-shared-state",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.25,
      "theme": "test-isolation",
      "scoreImpact": 3
    },
    {
      "category": "Testing",
      "severity": "major",
      "file": "./test/constants_test.dart",
      "line": 2,
      "message": "constants_test.dart imports audio_engine.dart to access kDrumPresets and kDefaultPresetIndices. These values are defined in the AudioEngine source file which imports platform-dependent packages (audioplayers, path_provider). This means the constants test will fail to compile or run on any headless CI host that lacks the platform plugin stubs for audioplayers, breaking coverage for otherwise-pure constant verification.",
      "suggestion": "Move kDrumPresets and kDefaultPresetIndices out of audio_engine.dart into constants.dart (or a separate drum_presets.dart). The test should import only the constants layer. This also removes the circular layering implied by a test that must pull in the full audio stack to check a numeric constant.",
      "evidence": "import 'package:sampler_sequencer/audio/audio_engine.dart';\nimport 'package:sampler_sequencer/constants.dart';\n// ...\ntest('kDrumPresets has 9 entries', () {\n  expect(kDrumPresets.length, 9, ...);\n});",
      "ruleId": "TEST-missing-coverage",
      "source": "llm",
      "effort": "small",
      "effortHours": 1,
      "theme": "test-quality",
      "scoreImpact": 3
    },
    {
      "category": "Testing",
      "severity": "major",
      "file": "./lib/audio/audio_exporter.dart",
      "line": 1,
      "message": "AudioExporter has no test coverage. It contains substantial pure logic: WAV parsing (_readWav), timeline computation (stepFrames, outputFrames), stereo mixing loop, peak normalisation, and WAV writing. These are all testable with in-memory byte arrays and do not require a real filesystem or audio stack.",
      "suggestion": "Add test/audio_exporter_test.dart covering: (1) _readWav rejects non-RIFF, non-WAVE, non-PCM inputs; (2) export mixes a single step at the correct frame offset given a known BPM; (3) normalisation scales output so the peak is 32767 when mix exceeds 1.0; (4) trim start/end offsets the source read window correctly.",
      "evidence": "// No test file references AudioExporter anywhere in the test suite.\n// Complex mixing logic in export() at lib/audio/audio_exporter.dart:107\n// is entirely untested including the normalisation path at line 203-207.",
      "ruleId": "TEST-missing-coverage",
      "source": "llm",
      "effort": "medium",
      "effortHours": 3,
      "theme": "missing-coverage",
      "scoreImpact": 6
    },
    {
      "category": "Testing",
      "severity": "major",
      "file": "./lib/audio/sample_library.dart",
      "line": 1,
      "message": "SampleLibrary has no test coverage. It contains business logic that is independently testable: index loading, migration from legacy files, addRecording path construction, rename, delete, and the JSON serialisation format. The real filesystem calls can be avoided by injecting the directory path or mocking the File/Directory API.",
      "suggestion": "Add test/sample_library_test.dart. Use a temporary in-memory directory or a test-scoped tmpdir. Cover: (1) init() creates the library directory; (2) addRecording copies the file and persists the name to index.json; (3) rename() updates the name without renaming the file; (4) delete() removes the file and updates the index; (5) _loadIndex() skips entries whose files no longer exist.",
      "evidence": "// No test file references SampleLibrary anywhere in the test suite.\n// Business logic in addRecording() at lib/audio/sample_library.dart:87\n// and _loadIndex() at line 34 are entirely untested.",
      "ruleId": "TEST-missing-coverage",
      "source": "llm",
      "effort": "medium",
      "effortHours": 2.5,
      "theme": "missing-coverage",
      "scoreImpact": 5
    },
    {
      "category": "Testing",
      "severity": "major",
      "file": "./test/sequencer_model_logic_test.dart",
      "line": 1,
      "message": "Several public SequencerModel methods have no test coverage: toggleMute, clearCustomSample, loadPreset, setTrim, clearTrim, setTrackVolume. These delegate to AudioEngine but also call notifyListeners() and _save(), meaning the listener notification and persistence paths are entirely unverified.",
      "suggestion": "Add test groups for each untested method. Since MockAudioEngine is already in place, the cost is low. For example: toggleMute should flip isMuted from false to true and call notifyListeners; setTrim should delegate to audio.setTrim with the supplied arguments; clearTrim should call audio.clearTrim and notify.",
      "evidence": "// From lib/models/sequencer_model.dart — methods with no corresponding tests:\nvoid toggleMute(int track) { ... notifyListeners(); _save(); }\nvoid loadPreset(int track, int presetIndex) { ... notifyListeners(); _save(); }\nvoid setTrim(int track, Duration start, Duration? end) { ... notifyListeners(); _save(); }\nvoid clearTrim(int track) { ... notifyListeners(); _save(); }",
      "ruleId": "TEST-missing-coverage",
      "source": "llm",
      "effort": "small",
      "effortHours": 1.5,
      "theme": "missing-coverage",
      "scoreImpact": 4
    },
    {
      "category": "Testing",
      "severity": "major",
      "file": "./test/audio_engine_dsp_test.dart",
      "line": 133,
      "message": "Four drum generator functions (generateRimShot, generateHiHatOpen, generateClap, generateTom) are present in dsp_utils.dart but have no sample-count or amplitude-range tests. generateKick808 and generateSnare are covered; the remaining four follow identical patterns and are equally testable.",
      "suggestion": "Add tests asserting (a) buf.length equals the expected sample count (120 ms, 600 ms, 220 ms, 400 ms respectively at 44100 Hz) and (b) all samples are within [-1.0, 1.0]. Follow the exact pattern already used for generateKick808 and generateSnare in the existing 'drum generators' group.",
      "evidence": "// Covered: generateKick808, generateKickHard, generateHiHatClosed, generateCowbell (count)\n//          generateKick808, generateSnare (amplitude bounds)\n// Missing:  generateRimShot, generateHiHatOpen, generateClap, generateTom\n//           — no count test, no amplitude-range test",
      "ruleId": "TEST-missing-coverage",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "missing-coverage",
      "scoreImpact": 2.5
    },
    {
      "category": "Testing",
      "severity": "minor",
      "file": "./test/sequencer_model_logic_test.dart",
      "line": 67,
      "message": "The 'notifies listeners and updates bpm' test adds a listener but never removes it before the test ends. If SequencerModel.dispose() is not called in a tearDown, the listener callback closure holds a reference into the test frame, which may affect subsequent tests or produce false-positive notification counts when tests share the same model instance across groups.",
      "suggestion": "Store the listener in a local variable and remove it in an addTearDown callback: final listener = () => notifyCount++; model.addListener(listener); addTearDown(() => model.removeListener(listener));",
      "evidence": "test('notifies listeners and updates bpm', () {\n  int notifyCount = 0;\n  model.addListener(() => notifyCount++);\n  model.setBpm(140);\n  expect(notifyCount, greaterThan(0), ...);\n  // No removeListener — listener leaks into subsequent tests\n});",
      "ruleId": "TEST-flaky-global-mocks",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.25,
      "theme": "test-isolation",
      "scoreImpact": 1.5
    },
    {
      "category": "Testing",
      "severity": "minor",
      "file": "./test/sequencer_model_logic_test.dart",
      "line": 93,
      "message": "Same listener leak as above: the 'notifies listeners and updates step state' test adds a listener without removing it. The same pattern also appears in the setStepVelocity notifies test (line 132) and the clearAllSteps notifies test (line 196).",
      "suggestion": "Apply addTearDown(() => model.removeListener(listener)) consistently in all three notification tests, or move listener setup/teardown into a shared helper.",
      "evidence": "test('notifies listeners and updates step state', () {\n  int notifyCount = 0;\n  model.addListener(() => notifyCount++);  // never removed\n  model.toggleStep(0, 0);\n  expect(notifyCount, greaterThan(0), ...);\n});",
      "ruleId": "TEST-flaky-global-mocks",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.25,
      "theme": "test-isolation",
      "scoreImpact": 1.5
    },
    {
      "category": "Testing",
      "severity": "minor",
      "file": "./test/sequencer_model_logic_test.dart",
      "line": 1,
      "message": "SequencerModel is constructed in setUp() but dispose() is never called in tearDown(). The model holds a Timer (_stepTimer) that could in theory fire after the test ends if a test leaves the model in a playing state. While no current test calls togglePlay(), the absence of tearDown disposal is a latent risk as the test suite grows.",
      "suggestion": "Add tearDown(() => model.dispose()); to the top-level setUp/tearDown pair. This also ensures the MockAudioEngine.dispose() stub is exercised, providing an implicit regression guard.",
      "evidence": "setUp(() {\n  SharedPreferences.setMockInitialValues({});\n  audio = MockAudioEngine();\n  // ... stubs ...\n  model = SequencerModel(audio: audio);\n});\n// No corresponding tearDown(() => model.dispose())",
      "ruleId": "TEST-flaky-shared-state",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.25,
      "theme": "test-isolation",
      "scoreImpact": 1.5
    },
    {
      "category": "Testing",
      "severity": "minor",
      "file": "./test/audio_engine_dsp_test.dart",
      "line": 111,
      "message": "dspEnv is tested for i=0 (full amplitude), i=totalSamples (near-zero), and monotonic decrease over [0, 50). The boundary case where i > totalSamples is not tested — the function is pure math (exp(-decayRate * i / totalSamples)) and would return a value less than the end-of-range value, but confirming this is not asserted. More importantly, the case totalSamples=0 (division by zero) is untested.",
      "suggestion": "Add a test for dspEnv with totalSamples=0 to verify it does not throw (or explicitly documents the precondition). Add a test for i > totalSamples to confirm the envelope continues to decay rather than wrapping or resetting.",
      "evidence": "group('dspEnv', () {\n  test('returns exactly 1.0 at i=0 ...', ...);\n  test('returns near zero at the end ...', ...);\n  test('is strictly monotonically decreasing ...', ...);\n  // Missing: i > totalSamples, totalSamples == 0\n});",
      "ruleId": "TEST-missing-coverage",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.25,
      "theme": "missing-coverage",
      "scoreImpact": 1
    },
    {
      "category": "Testing",
      "severity": "minor",
      "file": "./test/audio_engine_dsp_test.dart",
      "line": 12,
      "message": "buildWav is tested with an empty Float64List (0 samples) for header structure. The test for 'output length' uses 100 samples. There is no test for a very short buffer (1 or 2 samples) where kWavFadeSamples is clamped to numSamples/2 — the clamp path at dsp_utils.dart line 25 is exercised but the fade-in/fade-out monotonicity tests use n=2000, which never hits the clamp. The clamp boundary is therefore not covered.",
      "suggestion": "Add a test with n = 4 (less than 2 * kWavFadeSamples = 512) to verify that buildWav produces a valid WAV without panicking and that the first and last samples are still zero (fade correctly clamped).",
      "evidence": "// dsp_utils.dart line 25:\nfinal fadeSamples = kWavFadeSamples.clamp(0, numSamples ~/ 2);\n// test uses n = 2000 (>> 512) — clamp branch never taken in tests\nconst int n = 2000; // longer than 2 × kWavFadeSamples",
      "ruleId": "TEST-missing-coverage",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.25,
      "theme": "missing-coverage",
      "scoreImpact": 1
    },
    {
      "category": "Testing",
      "severity": "info",
      "file": "./test/constants_test.dart",
      "line": 1,
      "message": "constants_test.dart contains only value-equality assertions (expect(k, literal)). These tests provide a useful regression guard against accidental constant changes but offer no coverage of runtime behaviour. The test file name implies pure constant checking, which is fulfilled, but the dependency on audio_engine.dart (see separate finding) means this file's pass/fail is not truly isolated.",
      "suggestion": "Once kDrumPresets and kDefaultPresetIndices are moved to a constants file (see companion finding), this test file will become a fully isolated unit test with zero platform dependencies. No action needed on the assertions themselves.",
      "evidence": "test('kDrumPresets has 9 entries', () {\n  expect(kDrumPresets.length, 9, reason: ...);\n});\n// Pure value assertions — correct pattern, blocked only by import layering",
      "ruleId": "TEST-missing-coverage",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0,
      "theme": "test-quality",
      "scoreImpact": 0.5
    },
    {
      "category": "Testing",
      "severity": "info",
      "file": "./lib/audio/audio_recorder.dart",
      "line": 1,
      "message": "AppAudioRecorder is a thin wrapper with no tests. As a pure delegate with no logic of its own, the risk of a logic bug is low, but the public contract (hasPermission, start, stop, dispose signatures and the RecordConfig hardcoded values) is not asserted anywhere.",
      "suggestion": "Either document explicitly that AppAudioRecorder is excluded from testing due to its delegation-only nature, or add a single test that verifies the RecordConfig values (sampleRate: 44100, numChannels: 1, encoder: AudioEncoder.wav) are as expected — these are testable without a real microphone.",
      "evidence": "class AppAudioRecorder {\n  Future<void> start(String path) => _recorder.start(\n    const RecordConfig(\n      encoder: AudioEncoder.wav,\n      sampleRate: 44100,\n      numChannels: 1,\n    ),\n    path: path,\n  );\n}",
      "ruleId": "TEST-missing-coverage",
      "source": "llm",
      "effort": "trivial",
      "effortHours": 0.5,
      "theme": "missing-coverage",
      "scoreImpact": 0.5
    }
  ],
  "recommendations": [],
  "categoryScores": [
    {
      "category": "Security",
      "issueCount": 7,
      "deduction": 28.5,
      "maxWeight": 15,
      "grade": "F"
    },
    {
      "category": "Reliability",
      "issueCount": 7,
      "deduction": 30,
      "maxWeight": 10,
      "grade": "F"
    },
    {
      "category": "Performance",
      "issueCount": 5,
      "deduction": 20,
      "maxWeight": 10,
      "grade": "F"
    },
    {
      "category": "Maintainability",
      "issueCount": 10,
      "deduction": 19.5,
      "maxWeight": 5,
      "grade": "F"
    },
    {
      "category": "Testing",
      "issueCount": 14,
      "deduction": 32,
      "maxWeight": 5,
      "grade": "F"
    },
    {
      "category": "Architecture",
      "issueCount": 2,
      "deduction": 5,
      "maxWeight": 5,
      "grade": "F"
    },
    {
      "category": "Documentation",
      "issueCount": 1,
      "deduction": 0.8999999999999999,
      "maxWeight": 3,
      "grade": "C"
    }
  ],
  "technicalDebt": {
    "totalHours": 65,
    "hoursByCategory": {
      "Architecture": 4,
      "Maintainability": 10.25,
      "Documentation": 1,
      "Reliability": 13,
      "Performance": 18.5,
      "Security": 7.5,
      "Testing": 10.75
    },
    "hoursBySeverity": {
      "major": 30.5,
      "minor": 25.75,
      "info": 8.75
    }
  },
  "sourceBreakdown": {
    "analyzer": 0,
    "llm": 46,
    "total": 46
  },
  "analyzersRun": []
}
```