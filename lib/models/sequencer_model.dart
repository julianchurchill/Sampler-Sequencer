import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/audio_engine.dart';
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

class SequencerModel extends ChangeNotifier {
  int _bpm = kDefaultBpm;
  bool _isPlaying = false;
  bool _isLoading = false;

  /// Current playhead step (0–15) shown highlighted in the UI, or -1 when stopped.
  int _currentStep = -1;

  /// steps[track][step] — whether that step is active.
  final List<List<bool>> _steps = List.generate(
    kNumTracks,
    (_) => List.filled(kNumSteps, false),
  );

  final AudioEngine _audio = AudioEngine();
  Timer? _stepTimer;

  // ---- Getters ----

  int get bpm => _bpm;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  int get currentStep => _currentStep;

  bool stepEnabled(int track, int step) => _steps[track][step];
  bool hasCustomSample(int track) => _audio.hasCustomPath(track);
  String trackName(int track) => _audio.trackName(track);
  double trackVolume(int track) => _audio.trackVolume(track);
  bool hasTrim(int track) => _audio.hasTrim(track);
  Duration trimStart(int track) => _audio.trimStart(track);
  Duration? trimEnd(int track) => _audio.trimEnd(track);

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

    // Track sample selections and volumes
    for (int t = 0; t < kNumTracks; t++) {
      final customPath = prefs.getString('$_kPrefsTrackCustomPath$t');
      if (customPath != null) {
        final customName = prefs.getString('$_kPrefsTrackCustomName$t') ?? customPath.split('/').last;
        _audio.setCustomPathWithName(t, customPath, customName);
      } else {
        final presetIdx = prefs.getInt('$_kPrefsTrackPreset$t');
        if (presetIdx != null && presetIdx >= 0 && presetIdx < kDrumPresets.length) {
          _audio.setPreset(t, presetIdx);
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
    }

    notifyListeners();
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
      }
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

  /// Load a library sample with a known [path] and display [name].
  void loadCustomSample2(int track, String path, String name) {
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

  Future<Duration?> getTrackDuration(int track) => _audio.getTrackDuration(track);
  Future<void> previewTrim(int track, Duration start, Duration? end) =>
      _audio.previewTrim(track, start, end);
  Future<void> stopTrack(int track) => _audio.stopTrack(track);

  void clearAllSteps() {
    for (final row in _steps) {
      row.fillRange(0, row.length, false);
    }
    notifyListeners();
    _save();
  }

  // ---- Private helpers ----

  Duration get _stepDuration =>
      Duration(microseconds: (60000000 / (_bpm * kStepsPerQuarterNote)).round());

  Future<void> _play() async {
    try {
      if (!_audio.isReady) {
        // Fallback in case init() hasn't completed yet.
        _isLoading = true;
        notifyListeners();
        await _audio.init();
        _isLoading = false;
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
    notifyListeners();
  }

  void _tickStep() {
    if (!_isPlaying) return;
    _fireAndAdvance();
  }

  void _fireAndAdvance() {
    for (int t = 0; t < kNumTracks; t++) {
      if (_steps[t][_currentStep]) {
        _audio.trigger(t);
      }
    }
    notifyListeners();
    _currentStep = (_currentStep + 1) % kNumSteps;
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _audio.dispose();
    super.dispose();
  }
}
