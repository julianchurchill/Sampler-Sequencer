import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/audio_engine.dart';
import '../audio/audio_exporter.dart';
import '../constants.dart';

const _kPrefsSteps = 'sequencer_steps';
const _kPrefsBpm = 'sequencer_bpm';
// Per-track keys — append track index (0–3).
const _kPrefsTrackPreset = 'track_preset_';
const _kPrefsTrackCustomPath = 'track_custom_path_';
const _kPrefsTrackCustomName = 'track_custom_name_';
const _kPrefsTrackVolume = 'track_volume_';
const _kPrefsTrackTrimStart = 'track_trim_start_'; // milliseconds
const _kPrefsTrackTrimEnd = 'track_trim_end_';     // milliseconds, -1 = none
const _kPrefsTrackMuted = 'track_muted_';          // bool
const _kPrefsStepVelocity = 'step_vel_';           // comma-separated floats per track

class SequencerModel extends ChangeNotifier {
  int _bpm = kDefaultBpm;
  bool _isPlaying = false;
  bool _isLoading = false;

  /// Playhead step last fired by the sequencer (0–15), or -1 when stopped.
  ///
  /// Exposed as a [ValueNotifier] so [StepButton] can subscribe via
  /// [ValueListenableBuilder] and rebuild only the two buttons whose
  /// [isCurrent] state changes on each tick — instead of broadcasting
  /// [notifyListeners] to all 64 step buttons on every sequencer tick.
  final ValueNotifier<int> currentStepNotifier = ValueNotifier(-1);

  /// Internal counter: the step index that will fire on the NEXT tick.
  /// Kept separate from [currentStepNotifier] which tracks the last FIRED step.
  int _currentStep = -1;

  /// steps[track][step] — whether that step is active.
  final List<List<bool>> _steps = List.generate(
    kNumTracks,
    (_) => List.filled(kNumSteps, false),
  );

  /// Per-step velocity (0.0–1.0, default kDefaultStepVelocity).
  final List<List<double>> _stepVelocity = List.generate(
    kNumTracks,
    (_) => List.filled(kNumSteps, kDefaultStepVelocity),
  );

  late final AudioEngine _audio;
  Timer? _stepTimer;

  /// Non-null in debug builds when the most recent [_save] call failed.
  /// The UI should display this to the developer and call [clearSaveError].
  Object? _saveError;

  SequencerModel({AudioEngine? audio}) : _audio = audio ?? AudioEngine();

  // ---- Getters ----

  int get bpm => _bpm;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  int get currentStep => currentStepNotifier.value;

  bool stepEnabled(int track, int step) => _steps[track][step];
  double stepVelocity(int track, int step) => _stepVelocity[track][step];
  bool hasNonDefaultStepSettings(int track, int step) =>
      _stepVelocity[track][step] != kDefaultStepVelocity;
  bool hasCustomSample(int track) => _audio.hasCustomPath(track);
  String trackName(int track) => _audio.trackName(track);
  double trackVolume(int track) => _audio.trackVolume(track);
  bool hasTrim(int track) => _audio.hasTrim(track);
  Duration trimStart(int track) => _audio.trimStart(track);
  Duration? trimEnd(int track) => _audio.trimEnd(track);
  bool isMuted(int track) => _audio.isMuted(track);
  Object? get saveError => _saveError;

  /// Clear the last save error after it has been displayed to the user.
  void clearSaveError() => _saveError = null;

  /// For testing only: simulate a save error without going through SharedPreferences.
  @visibleForTesting
  void setSaveErrorForTest(Object e) {
    _saveError = e;
    notifyListeners();
  }

  // ---- Persistence ----

  /// Call once after construction to restore previously saved state.
  Future<void> init() async {
    // Initialise the audio engine first so that player instances exist before
    // we try to restore per-track volume (setTrackVolume accesses _players).
    _isLoading = true;
    notifyListeners();
    try {
      await _audio.init();
    } finally {
      _isLoading = false;
    }

    final prefs = await SharedPreferences.getInstance();
    await _restoreStepsAndBpm(prefs);
    await _restoreTrackState(prefs);
    notifyListeners();
  }

  /// Restore step grid and BPM from [prefs].
  Future<void> _restoreStepsAndBpm(SharedPreferences prefs) async {
    // Steps
    final stepsStr = prefs.getString(_kPrefsSteps);
    if (stepsStr != null) {
      final tracks = stepsStr.split('|');
      for (int t = 0; t < kNumTracks && t < tracks.length; t++) {
        for (int s = 0; s < kNumSteps && s < tracks[t].length; s++) {
          _steps[t][s] = tracks[t][s] == '1';
        }
      }
    }

    // BPM
    final savedBpm = prefs.getInt(_kPrefsBpm);
    if (savedBpm != null) {
      _bpm = savedBpm.clamp(kMinBpm, kMaxBpm);
    }
  }

  /// Restore per-track sample selection, volume, trim, mute, and velocity from [prefs].
  Future<void> _restoreTrackState(SharedPreferences prefs) async {
    for (int t = 0; t < kNumTracks; t++) {
      final customPath = prefs.getString('$_kPrefsTrackCustomPath$t');
      // Guard against stale paths that no longer exist on disk (e.g. after
      // app re-install or the user deleting the file externally).
      if (customPath != null && await File(customPath).exists()) {
        final customName = prefs.getString('$_kPrefsTrackCustomName$t') ?? customPath.split('/').last;
        await _audio.setCustomPathWithName(t, customPath, customName);
      } else {
        final presetIdx = prefs.getInt('$_kPrefsTrackPreset$t');
        if (presetIdx != null && presetIdx >= 0 && presetIdx < kDrumPresets.length) {
          await _audio.setPreset(t, presetIdx);
        }
      }
      final vol = prefs.getDouble('$_kPrefsTrackVolume$t');
      if (vol != null) await _audio.setTrackVolume(t, vol);
      final trimStartMs = prefs.getInt('$_kPrefsTrackTrimStart$t');
      final trimEndMs = prefs.getInt('$_kPrefsTrackTrimEnd$t');
      if (trimStartMs != null || trimEndMs != null) {
        _audio.setTrim(
          t,
          Duration(milliseconds: trimStartMs ?? 0),
          (trimEndMs != null && trimEndMs >= 0)
              ? Duration(milliseconds: trimEndMs)
              : null,
        );
      }
      final muted = prefs.getBool('$_kPrefsTrackMuted$t');
      if (muted != null) _audio.setMuted(t, muted);
      final velStr = prefs.getString('$_kPrefsStepVelocity$t');
      if (velStr != null) {
        final parts = velStr.split(',');
        for (int s = 0; s < kNumSteps && s < parts.length; s++) {
          _stepVelocity[t][s] = double.tryParse(parts[s]) ?? kDefaultStepVelocity;
        }
      }
    }
  }

  void _save() {
    SharedPreferences.getInstance().then((prefs) {
      // Steps
      final stepsStr = _steps
          .map((track) => track.map((s) => s ? '1' : '0').join())
          .join('|');
      prefs.setString(_kPrefsSteps, stepsStr);

      // BPM
      prefs.setInt(_kPrefsBpm, _bpm);

      // Track sample selections and volumes
      for (int t = 0; t < kNumTracks; t++) {
        final path = _audio.customPath(t);
        if (path != null) {
          prefs.setString('$_kPrefsTrackCustomPath$t', path);
          prefs.setString('$_kPrefsTrackCustomName$t', _audio.trackName(t));
          prefs.remove('$_kPrefsTrackPreset$t');
        } else {
          prefs.setInt('$_kPrefsTrackPreset$t', _audio.presetIndex(t));
          prefs.remove('$_kPrefsTrackCustomPath$t');
          prefs.remove('$_kPrefsTrackCustomName$t');
        }
        prefs.setDouble('$_kPrefsTrackVolume$t', _audio.trackVolume(t));
        prefs.setInt('$_kPrefsTrackTrimStart$t', _audio.trimStart(t).inMilliseconds);
        final end = _audio.trimEnd(t);
        prefs.setInt('$_kPrefsTrackTrimEnd$t', end != null ? end.inMilliseconds : -1);
        prefs.setBool('$_kPrefsTrackMuted$t', _audio.isMuted(t));
        prefs.setString('$_kPrefsStepVelocity$t',
            _stepVelocity[t].map((v) => v.toStringAsFixed(3)).join(','));
      }
    }).catchError((Object e) {
      debugPrint('SequencerModel _save error: $e');
      _saveError = e;
      notifyListeners();
    });
  }

  // ---- Public actions ----

  Future<void> togglePlay() async {
    if (_isPlaying) {
      _stop();
    } else {
      await _play();
    }
  }

  void toggleStep(int track, int step) {
    _steps[track][step] = !_steps[track][step];
    notifyListeners();
    _save();
  }

  void setBpm(int bpm) {
    _bpm = bpm.clamp(kMinBpm, kMaxBpm);
    notifyListeners();
    _save();
    if (_isPlaying) {
      _stepTimer?.cancel();
      _stepTimer = Timer.periodic(_stepDuration, (_) => _tickStep());
    }
  }

  Future<void> setTrackVolume(int track, double volume) async {
    await _audio.setTrackVolume(track, volume);
    notifyListeners();
    _save();
  }

  void loadPreset(int track, int presetIndex) {
    _audio.setPreset(track, presetIndex);
    notifyListeners();
    _save();
  }

  Future<void> loadCustomSample(int track) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path != null) {
        _audio.setCustomPath(track, path);
        notifyListeners();
        _save();
      }
    } catch (e) {
      debugPrint('File picker error: $e');
    }
  }

  /// Load a sample from the in-app library with a known [path] and display [name].
  void loadLibrarySample(int track, String path, String name) {
    _audio.setCustomPathWithName(track, path, name);
    notifyListeners();
    _save();
  }

  void clearCustomSample(int track) {
    _audio.clearCustomPath(track);
    notifyListeners();
    _save();
  }

  void setTrim(int track, Duration start, Duration? end) {
    _audio.setTrim(track, start, end);
    notifyListeners();
    _save();
  }

  void clearTrim(int track) {
    _audio.clearTrim(track);
    notifyListeners();
    _save();
  }

  void toggleMute(int track) {
    _audio.setMuted(track, !_audio.isMuted(track));
    notifyListeners();
    _save();
  }

  void setStepVelocity(int track, int step, double velocity) {
    _stepVelocity[track][step] = velocity.clamp(0.0, 1.0);
    notifyListeners();
    _save();
  }

  Future<Duration?> getTrackDuration(int track) => _audio.getTrackDuration(track);

  /// Render [numLoops] loops of the current sequence to a WAV file at [outputPath].
  /// [unsupportedTracks] is populated with track indices whose samples could not
  /// be decoded (non-WAV files) and were silenced in the mix.
  Future<void> exportWav({
    required int numLoops,
    required String outputPath,
    required List<int> unsupportedTracks,
    void Function(double)? onProgress,
  }) =>
      AudioExporter.export(
        samplePaths: List.generate(kNumTracks, _audio.samplePath),
        volumes: List.generate(kNumTracks, _audio.trackVolume),
        trimStarts: List.generate(kNumTracks, _audio.trimStart),
        trimEnds: List.generate(kNumTracks, _audio.trimEnd),
        steps: _steps,
        bpm: _bpm,
        numLoops: numLoops,
        outputPath: outputPath,
        unsupportedTracks: unsupportedTracks,
        onProgress: onProgress,
      );
  Future<void> previewTrim(int track, Duration start, Duration? end) =>
      _audio.previewTrim(track, start, end);
  Future<void> stopTrack(int track) => _audio.stopTrack(track);
  Stream<Duration> get positionStream => _audio.positionStream;

  void clearAllSteps() {
    for (final row in _steps) {
      row.fillRange(0, row.length, false);
    }
    for (final row in _stepVelocity) {
      row.fillRange(0, row.length, kDefaultStepVelocity);
    }
    notifyListeners();
    _save();
  }

  // ---- Private helpers ----

  Duration get _stepDuration => stepDuration;

  @visibleForTesting
  Duration get stepDuration =>
      Duration(microseconds: (60000000 / (_bpm * kStepsPerQuarterNote)).round());

  Future<void> _play() async {
    try {
      if (!_audio.isReady) {
        debugPrint('SequencerModel._play(): audio engine not ready, aborting playback');
        return;
      }
      _isPlaying = true;
      _currentStep = 0;
      _fireAndAdvance();
      _stepTimer = Timer.periodic(_stepDuration, (_) => _tickStep());
    } catch (e) {
      debugPrint('Sequencer start error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _stop() {
    _stepTimer?.cancel();
    _stepTimer = null;
    _isPlaying = false;
    _currentStep = -1;
    currentStepNotifier.value = -1;
    _audio.stopAll();
    notifyListeners();
  }

  void _tickStep() {
    if (!_isPlaying) return;
    _fireAndAdvance();
  }

  void _fireAndAdvance() {
    for (int t = 0; t < kNumTracks; t++) {
      if (_steps[t][_currentStep]) {
        _audio.trigger(t, velocity: _stepVelocity[t][_currentStep]);
      }
    }
    // Update only the playhead notifier — NOT notifyListeners().
    // This wakes only the two StepButtons whose isCurrent state changed
    // (previous step → false, new step → true) via ValueListenableBuilder,
    // instead of triggering all 64 context.select evaluations on every tick.
    currentStepNotifier.value = _currentStep;
    _currentStep = (_currentStep + 1) % kNumSteps;
  }

  /// Exposed for testing only — exercises [_fireAndAdvance] directly so tests
  /// can verify tick behaviour without waiting for [Timer.periodic] to fire.
  @visibleForTesting
  void fireAndAdvanceForTest() => _fireAndAdvance();

  @override
  void dispose() {
    _stepTimer?.cancel();
    currentStepNotifier.dispose();
    _audio.dispose();
    super.dispose();
  }
}
