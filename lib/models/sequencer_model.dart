import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../audio/audio_engine.dart';
import '../constants.dart';

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
  }

  void setBpm(int bpm) {
    _bpm = bpm.clamp(kMinBpm, kMaxBpm);
    notifyListeners();
    if (_isPlaying) {
      _stepTimer?.cancel();
      _stepTimer = Timer.periodic(_stepDuration, (_) => _tickStep());
    }
  }

  void loadPreset(int track, int presetIndex) {
    _audio.setPreset(track, presetIndex);
    notifyListeners();
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
      }
    } catch (e) {
      debugPrint('File picker error: $e');
    }
  }

  /// Load a library sample with a known [path] and display [name].
  void loadCustomSample2(int track, String path, String name) {
    _audio.setCustomPathWithName(track, path, name);
    notifyListeners();
  }

  void clearCustomSample(int track) {
    _audio.clearCustomPath(track);
    notifyListeners();
  }

  void clearAllSteps() {
    for (final row in _steps) {
      row.fillRange(0, row.length, false);
    }
    notifyListeners();
  }

  // ---- Private helpers ----

  Duration get _stepDuration =>
      Duration(microseconds: (60000000 / (_bpm * kStepsPerQuarterNote)).round());

  Future<void> _play() async {
    _isLoading = true;
    notifyListeners();
    try {
      if (!_audio.isReady) {
        await _audio.init();
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
