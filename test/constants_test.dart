import 'package:flutter_test/flutter_test.dart';
import 'package:sampler_sequencer/audio/audio_engine.dart';
import 'package:sampler_sequencer/constants.dart';

void main() {
  group('constants', () {
    test('kNumTracks is 4', () => expect(kNumTracks, 4));
    test('kNumSteps is 16', () => expect(kNumSteps, 16));
    test('kDefaultBpm is 120', () => expect(kDefaultBpm, 120));
    test('kMinBpm is 40', () => expect(kMinBpm, 40));
    test('kMaxBpm is 300', () => expect(kMaxBpm, 300));
    test('kDefaultStepVelocity is 1.0', () => expect(kDefaultStepVelocity, 1.0));
    test('kStepsPerQuarterNote is 4.0', () => expect(kStepsPerQuarterNote, 4.0));

    test('kDrumPresets has 9 entries', () => expect(kDrumPresets.length, 9));

    test('kDefaultPresetIndices are all in-bounds', () {
      for (final idx in kDefaultPresetIndices) {
        expect(idx, greaterThanOrEqualTo(0));
        expect(idx, lessThan(kDrumPresets.length));
      }
    });

    test('kTrackColors has kNumTracks entries', () {
      expect(kTrackColors.length, kNumTracks);
    });

    test('kTrackColorsDim has kNumTracks entries', () {
      expect(kTrackColorsDim.length, kNumTracks);
    });
  });
}
