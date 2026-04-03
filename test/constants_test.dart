import 'package:flutter_test/flutter_test.dart';
import 'package:sampler_sequencer/constants.dart';

void main() {
  group('constants', () {
    test('kNumTracks is 4', () {
      expect(kNumTracks, 4,
          reason: 'App is built for exactly 4 tracks; changing this would break AudioEngine, UI layout, and persistence keys');
    });

    test('kNumSteps is 16', () {
      expect(kNumSteps, 16,
          reason: 'Sequencer grid is 16 steps; changing this breaks step storage format');
    });

    test('kDefaultBpm is 120', () {
      expect(kDefaultBpm, 120,
          reason: 'Default tempo should be 120 BPM — a standard musical default');
    });

    test('kMinBpm is 40', () {
      expect(kMinBpm, 40,
          reason: 'Minimum BPM should be 40 to prevent excessively slow tempos');
    });

    test('kMaxBpm is 300', () {
      expect(kMaxBpm, 300,
          reason: 'Maximum BPM should be 300 to prevent excessively fast tempos');
    });

    test('kDefaultStepVelocity is 1.0', () {
      expect(kDefaultStepVelocity, 1.0,
          reason: 'Default velocity should be full volume (1.0); changing this would silently alter the sound of all existing patterns');
    });

    test('kStepsPerQuarterNote is 4.0', () {
      expect(kStepsPerQuarterNote, 4.0,
          reason: 'Each step represents a 16th note (4 per quarter note); changing this alters the tempo formula');
    });

    test('kDrumPresets has 9 entries', () {
      expect(kDrumPresets.length, 9,
          reason: 'Expected 9 built-in drum presets: Kick808, KickHard, Snare, RimShot, HHClosed, HHOpen, Clap, Tom, Cowbell');
    });

    test('all kDefaultPresetIndices are valid indices into kDrumPresets', () {
      for (int i = 0; i < kDefaultPresetIndices.length; i++) {
        final idx = kDefaultPresetIndices[i];
        expect(idx, greaterThanOrEqualTo(0),
            reason: 'kDefaultPresetIndices[$i] = $idx is negative — not a valid preset index');
        expect(idx, lessThan(kDrumPresets.length),
            reason: 'kDefaultPresetIndices[$i] = $idx is out of bounds (kDrumPresets has ${kDrumPresets.length} entries)');
      }
    });

    test('kTrackColors has one entry per track', () {
      expect(kTrackColors.length, kNumTracks,
          reason: 'kTrackColors must have exactly kNumTracks ($kNumTracks) entries — one colour per track');
    });

    test('kTrackColorsDim has one entry per track', () {
      expect(kTrackColorsDim.length, kNumTracks,
          reason: 'kTrackColorsDim must have exactly kNumTracks ($kNumTracks) entries — one dim colour per track');
    });
  });
}
