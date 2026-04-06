# TODO

## Bugs

- [ ] if the sample is changed on a track then it doesn't always play on all steps, it is very non-deterministic

## General

- [ ] normalise sample automatically after recording

## UI

- [ ] show waveform of original sample when trimming
- [x] hide the version number display behind a (i), click it to show overlay of version details. include the build timestamp in the version number display

## Developer

- [ ] add dev container configuration to this repository so that any contributor can easily run the same development environment. This also provides a way to sandbox Claude or any other AI agent being run locally.
- [ ] incorporate <https://tiny-brain.com> - provides quality reviews (see [Quality Report 2026-04-02](#quality-report-2026-04-02)) and other persona based agent features
- [ ] iOS app creation by manually triggered GitHub action - at least needs Apple Dev account (£99p/y)

## Other

- [x] Added to TODO.md

## Quality Report 2026-04-02

For details and suggested fixes see `docs\quality\runs\2026-04-02\16-56\quality.md`

### Architecture

- [x] **minor**: AudioExporter contains its own private WAV parser (_readWav, _WavData) that duplicates knowledge already present in dsp_utils.dart (buildWav)
- [x] **minor**: AudioExporter.export() uses hardcoded literal 4 / 16 for track/step counts instead of kNumTracks / kNumSteps
- [x] **major**: Track count is hardcoded as the literal integer 4 in at least seven places inside AudioEngine

### Maintainability

- [ ] **info**: The comment at line 189 inside init() still reads 'Two low-latency SoundPool players per track (8 total).' but the code was updated to use _kSlotsPerTrack = 6 per track (24 total)
- [x] **minor**: _SoundPickerSheetState is a long method / god-class concern within track_row.dart
- [x] **minor**: trigger() has a cyclomatic complexity of approximately 14
- [x] **major**: loadCustomSample2 is a poorly-named method
- [x] **minor**: SampleEntry exposes mutable fields (String path, String name) on a public class
- [x] **minor**: Random seed literals (42, 99, 7, 13, 55) are scattered across six drum generator functions with no named constants or comments explaining their significance
- [x] **minor**: SequencerModel.init() is approximately 65 lines long and mixes three concerns: audio engine initialisation, SharedPreferences restoration for steps and BPM, and per-track state restoration
- [x] **minor**: In _togglePreview(), the local variable effectiveEndMs is computed to resolve the null end case, but this same null-resolution logic is duplicated at line 135 in _applyTrim() (endMs < dur.inMilliseconds ? Duration(milliseconds: endMs) : null)
- [x] **major**: positionStream(int track) accepts a track parameter but completely ignores it, always returning _previewPlayer.onPositionChanged
- [x] **major**: _save() uses fire-and-forget SharedPreferences.getInstance().then() with no error handling

### Documentation

- [x] **minor**: The Architecture section's directory tree is stale

### Reliability

- [ ] **info**: AudioEngine.init() synthesises all 9 preset WAV files and writes them to the temp directory on every cold start
- [x] **minor**: getTrackDuration() calls _previewPlayer.setSource() without stopping or checking whether the preview player is currently playing
- [x] **minor**: _loadIndex() calls File(path).exists() sequentially for every index entry, one await per file
- [x] **minor**: _play() calls _audio.init() a second time as a fallback if isReady is false
- [x] **major**: Fire-and-forget _save() swallows all SharedPreferences errors silently
- [x] **major**: _schedulePlayerModeSwitch is fire-and-forget: _rebuildPlayer is unawaited
- [x]  **major**: In the trimmed mediaPlayer path of trigger(), setSource(DeviceFileSource(path)) is called on every trigger

### Performance

- [ ] **info**: AudioExporter.export() runs entirely on the calling isolate (the Flutter UI isolate)
- [x] **minor**: _fireAndAdvance() calls notifyListeners() on every sequencer tick to update the playhead highlight
- [x] **minor**: setTrackVolume() applies the volume change sequentially across all _kSlotsPerTrack players (6 awaits in a loop)
- [x] **major**: The entire mix buffer is allocated as a Float64List in memory before conversion
- [x] **major**: WAV PCM samples are serialised into a ByteData buffer one Int16 at a time (O(n) individual setInt16 calls), then added to the file sink

### Security

- [ ] **minor**: User-supplied file path from file picker is used directly in DeviceFileSource without sanitization
- [ ] **minor**: Export output path is constructed from user-controlled timestamp but written without validating the parent directory
- [ ] **info**: File extension extracted from user-provided temp path via string split without validation
- [ ] **info**: Several dependencies use caret version ranges (e.g. ^6.0.0) which allow automatic minor/patch upgrades
- [x] **minor**: Exception details leaked to user in export error snackbar
- [x] **minor**: Custom file path restored from SharedPreferences is used without existence or validity check
- [x] **major**: Deserialization of untrusted JSON index file without schema validation

### Testing

- [ ] **info**: constants_test.dart contains only value-equality assertions (expect(k, literal))
- [ ] **info**: AppAudioRecorder is a thin wrapper with no tests
- [x] **minor**: The 'notifies listeners and updates bpm' test adds a listener but never removes it before the test ends
- [x] **minor**: Same listener leak as above: the 'notifies listeners and updates step state' test adds a listener without removing it
- [x] **minor**: SequencerModel is constructed in setUp() but dispose() is never called in tearDown()
- [x] **minor**: dspEnv is tested for i=0 (full amplitude), i=totalSamples (near-zero), and monotonic decrease over [0, 50)
- [x] **minor**: buildWav is tested with an empty Float64List (0 samples) for header structure
- [x] **major**: MockAudioEngine is configured in setUp but mock state is never reset between tests
- [x] **major**: Shared mutable state at describe scope: wav and pcm are declared at the top of the 'buildWav fade envelope' group and mutated in setUp()
- [x] **major**: constants_test.dart imports audio_engine.dart to access kDrumPresets and kDefaultPresetIndices
- [x] **major**: AudioExporter has no test coverage
- [x] **major**: SampleLibrary has no test coverage
- [x] **major**: Several public SequencerModel methods have no test coverage: toggleMute, clearCustomSample, loadPreset, setTrim, clearTrim, setTrackVolume
- [x] **major**: Four drum generator functions (generateRimShot, generateHiHatOpen, generateClap, generateTom) are present in dsp_utils.dart but have no sample-count or amplitude-range tests
