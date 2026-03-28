import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sequencer/flutter_sequencer.dart';

import '../constants.dart';

// ---------------------------------------------------------------------------
// Default SFZ instruments (synthesised oscillators — no sample files needed)
// ---------------------------------------------------------------------------

Sfz _kickSfz() => Sfz(groups: [
      SfzGroup(regions: [
        SfzRegion(
          sample: '*sine',
          lokey: 0,
          hikey: 127,
          otherOpcodes: {
            // Transpose 2 octaves down → ~65 Hz bass kick
            'tune': '-2400',
            'ampeg_attack': '0.001',
            'ampeg_decay': '0.5',
            'ampeg_sustain': '0',
            'ampeg_release': '0.01',
            'volume': '6',
          },
        ),
      ]),
    ]);

Sfz _snareSfz() => Sfz(groups: [
      SfzGroup(regions: [
        SfzRegion(
          sample: '*noise',
          lokey: 0,
          hikey: 127,
          otherOpcodes: {
            'ampeg_attack': '0.001',
            'ampeg_decay': '0.15',
            'ampeg_sustain': '0',
            'ampeg_release': '0.01',
          },
        ),
      ]),
    ]);

Sfz _hiHatClosedSfz() => Sfz(groups: [
      SfzGroup(regions: [
        SfzRegion(
          sample: '*noise',
          lokey: 0,
          hikey: 127,
          otherOpcodes: {
            'ampeg_attack': '0.001',
            'ampeg_decay': '0.06',
            'ampeg_sustain': '0',
            'ampeg_release': '0.01',
            'fil_type': 'hpf_2p',
            'cutoff': '6000',
          },
        ),
      ]),
    ]);

Sfz _hiHatOpenSfz() => Sfz(groups: [
      SfzGroup(regions: [
        SfzRegion(
          sample: '*noise',
          lokey: 0,
          hikey: 127,
          otherOpcodes: {
            'ampeg_attack': '0.001',
            'ampeg_decay': '0.6',
            'ampeg_sustain': '0.05',
            'ampeg_release': '0.2',
            'fil_type': 'hpf_2p',
            'cutoff': '5000',
          },
        ),
      ]),
    ]);

final List<Sfz Function()> _defaultSfzBuilders = [
  _kickSfz,
  _snareSfz,
  _hiHatClosedSfz,
  _hiHatOpenSfz,
];

// ---------------------------------------------------------------------------
// SequencerModel
// ---------------------------------------------------------------------------

class SequencerModel extends ChangeNotifier {
  int _bpm = kDefaultBpm;
  bool _isPlaying = false;
  bool _isLoading = false;

  /// Current playhead step (0–15), or -1 when stopped.
  int _currentStep = -1;

  /// steps[track][step] — whether that step is active.
  final List<List<bool>> _steps = List.generate(
    kNumTracks,
    (_) => List.filled(kNumSteps, false),
  );

  /// Optional custom sample file path per track (null → use synth default).
  final List<String?> _samplePaths = List.filled(kNumTracks, null);

  Sequence? _sequence;
  List<Track>? _tracks;
  Timer? _positionTimer;

  // ---- Getters ----

  int get bpm => _bpm;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  int get currentStep => _currentStep;

  bool stepEnabled(int track, int step) => _steps[track][step];
  String? samplePath(int track) => _samplePaths[track];
  bool hasSample(int track) => _samplePaths[track] != null;

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
    if (_isPlaying && _tracks != null) {
      _updateTrackEvents(track);
    }
  }

  void setBpm(int bpm) {
    _bpm = bpm.clamp(kMinBpm, kMaxBpm);
    notifyListeners();
    _sequence?.setTempo(_internalTempo(_bpm));
  }

  Future<void> loadSample(int trackIdx) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path != null) {
        _samplePaths[trackIdx] = path;
        notifyListeners();
        if (_isPlaying) await _rebuildSequenceAndResume();
      }
    } catch (e) {
      debugPrint('File picker error: $e');
    }
  }

  void clearSample(int trackIdx) {
    _samplePaths[trackIdx] = null;
    notifyListeners();
    if (_isPlaying) _rebuildSequenceAndResume();
  }

  void clearAllSteps() {
    for (final row in _steps) {
      row.fillRange(0, row.length, false);
    }
    notifyListeners();
    if (_isPlaying && _tracks != null) {
      for (int t = 0; t < kNumTracks; t++) {
        _updateTrackEvents(t);
      }
    }
  }

  // ---- Private helpers ----

  /// Internal tempo: 1 step = 1 internal beat, and steps are 16th notes,
  /// so internal BPM = displayBpm × 4.
  static double _internalTempo(int displayBpm) =>
      displayBpm * kStepsPerQuarterNote;

  Future<void> _play() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _buildSequence();
      _sequence!.play();
      _isPlaying = true;
      _startPositionTimer();
    } catch (e) {
      debugPrint('Sequencer start error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _stop() {
    _positionTimer?.cancel();
    _positionTimer = null;
    _sequence?.stop();
    _isPlaying = false;
    _currentStep = -1;
    notifyListeners();
  }

  BaseInstrument _buildInstrument(int idx) {
    final path = _samplePaths[idx];
    if (path != null) {
      final lastSlash = path.lastIndexOf('/');
      final dir = path.substring(0, lastSlash);
      final file = path.substring(lastSlash + 1);
      return RuntimeSfzInstrument(
        id: kTrackNames[idx],
        sampleRoot: dir,
        isAsset: false,
        sfz: Sfz(groups: [
          SfzGroup(regions: [
            SfzRegion(
              sample: file,
              lokey: 0,
              hikey: 127,
              otherOpcodes: {
                'ampeg_attack': '0.001',
                'ampeg_decay': '1.0',
                'ampeg_sustain': '0',
                'ampeg_release': '0.1',
              },
            ),
          ]),
        ]),
      );
    }
    return RuntimeSfzInstrument(
      id: kTrackNames[idx],
      sampleRoot: '/',
      isAsset: false,
      sfz: _defaultSfzBuilders[idx](),
    );
  }

  Future<void> _buildSequence() async {
    _sequence?.dispose();
    _sequence = Sequence(
      tempo: _internalTempo(_bpm),
      endBeat: kSequenceEndBeat,
    );
    final instruments = List.generate(kNumTracks, _buildInstrument);
    _tracks = await _sequence!.createTracks(instruments);
    for (int t = 0; t < kNumTracks; t++) {
      _fillTrack(t);
    }
    _sequence!.setLoop(0, kSequenceEndBeat);
  }

  void _fillTrack(int trackIdx) {
    final track = _tracks![trackIdx];
    for (int s = 0; s < kNumSteps; s++) {
      if (_steps[trackIdx][s]) {
        track.addNote(
          noteNumber: 60,
          velocity: 100,
          startBeat: s.toDouble(),
          durationBeats: 0.9,
        );
      }
    }
  }

  /// Update a single track's events without rebuilding the whole sequence.
  void _updateTrackEvents(int trackIdx) {
    final track = _tracks![trackIdx];
    track.clearEvents();
    _fillTrack(trackIdx);
    track.syncBuffer();
  }

  /// Rebuild all tracks (needed when an instrument changes).
  Future<void> _rebuildSequenceAndResume() async {
    _sequence?.pause();
    await _buildSequence();
    _sequence!.play();
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (_sequence == null || !_isPlaying) return;
      final beat = _sequence!.getBeat();
      final step = beat.floor() % kNumSteps;
      if (step != _currentStep) {
        _currentStep = step;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _sequence?.dispose();
    super.dispose();
  }
}
