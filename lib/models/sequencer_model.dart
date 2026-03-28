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
  bool hasSample(int track) => _audio.customPath(track) != null;

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
      // Restart periodic timer with updated interval (no extra hit).
      _stepTimer?.cancel();
      _stepTimer = Timer.periodic(_stepDuration, (_) => _tickStep());
    }
  }

  Future<void> loadSample(int trackIdx) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path != null) {
        _audio.setCustomPath(trackIdx, path);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('File picker error: $e');
    }
  }

  void clearSample(int trackIdx) {
    _audio.setCustomPath(trackIdx, null);
    notifyListeners();
  }

  void clearAllSteps() {
    for (final row in _steps) {
      row.fillRange(0, row.length, false);
    }
    notifyListeners();
  }

  // ---- Private helpers ----

  /// Duration of one 16th-note step at current BPM.
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
      // Start at step 0 and fire it immediately, then set periodic timer.
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

  /// Timer callback — fire audio, highlight step, then advance.
  void _tickStep() {
    if (!_isPlaying) return;
    _fireAndAdvance();
  }

  void _fireAndAdvance() {
    // Trigger all active tracks for the current step.
    for (int t = 0; t < kNumTracks; t++) {
      if (_steps[t][_currentStep]) {
        _audio.trigger(t);
      }
    }
    // Notify UI to highlight this step.
    notifyListeners();
    // Advance to next step (will be highlighted on the following tick).
    _currentStep = (_currentStep + 1) % kNumSteps;
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _audio.dispose();
    super.dispose();
  }
}
