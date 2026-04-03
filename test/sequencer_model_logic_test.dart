import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sampler_sequencer/audio/audio_engine.dart';
import 'package:sampler_sequencer/constants.dart';
import 'package:sampler_sequencer/models/sequencer_model.dart';

class MockAudioEngine extends Mock implements AudioEngine {}

void main() {
  late MockAudioEngine audio;
  late SequencerModel model;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    audio = MockAudioEngine();

    when(() => audio.isReady).thenReturn(false);
    when(() => audio.isMuted(any())).thenReturn(false);
    when(() => audio.trackVolume(any())).thenReturn(1.0);
    when(() => audio.trackName(any())).thenReturn('Test');
    when(() => audio.hasCustomPath(any())).thenReturn(false);
    when(() => audio.customPath(any())).thenReturn(null);
    when(() => audio.presetIndex(any())).thenReturn(0);
    when(() => audio.hasTrim(any())).thenReturn(false);
    when(() => audio.trimStart(any())).thenReturn(Duration.zero);
    when(() => audio.trimEnd(any())).thenReturn(null);
    when(() => audio.setMuted(any(), any())).thenReturn(null);

    model = SequencerModel(audio: audio);
  });

  // -------------------------------------------------------------------------
  group('setBpm', () {
    test('clamps a value below kMinBpm up to kMinBpm', () {
      model.setBpm(0);
      expect(model.bpm, kMinBpm,
          reason: 'setBpm(0) should clamp to kMinBpm ($kMinBpm), not store an invalid tempo');
    });

    test('clamps a value above kMaxBpm down to kMaxBpm', () {
      model.setBpm(9999);
      expect(model.bpm, kMaxBpm,
          reason: 'setBpm(9999) should clamp to kMaxBpm ($kMaxBpm), not store an invalid tempo');
    });

    test('stores a valid mid-range value unchanged', () {
      model.setBpm(140);
      expect(model.bpm, 140,
          reason: 'setBpm(140) should store 140 — it is within [kMinBpm, kMaxBpm]');
    });

    test('accepts the exact lower boundary kMinBpm', () {
      model.setBpm(kMinBpm);
      expect(model.bpm, kMinBpm,
          reason: 'setBpm(kMinBpm) should store $kMinBpm without clamping');
    });

    test('accepts the exact upper boundary kMaxBpm', () {
      model.setBpm(kMaxBpm);
      expect(model.bpm, kMaxBpm,
          reason: 'setBpm(kMaxBpm) should store $kMaxBpm without clamping');
    });

    test('notifies listeners and updates bpm', () {
      int notifyCount = 0;
      model.addListener(() => notifyCount++);
      model.setBpm(140);
      expect(notifyCount, greaterThan(0),
          reason: 'setBpm should call notifyListeners so the UI can redraw');
      expect(model.bpm, 140,
          reason: 'bpm should be 140 after setBpm(140)');
    });
  });

  // -------------------------------------------------------------------------
  group('toggleStep', () {
    test('activates an inactive step', () {
      model.toggleStep(0, 0);
      expect(model.stepEnabled(0, 0), isTrue,
          reason: 'toggleStep on an inactive step should activate it');
    });

    test('deactivates an active step on second toggle', () {
      model.toggleStep(0, 0);
      model.toggleStep(0, 0);
      expect(model.stepEnabled(0, 0), isFalse,
          reason: 'Two toggles should return the step to its original inactive state');
    });

    test('notifies listeners and updates step state', () {
      int notifyCount = 0;
      model.addListener(() => notifyCount++);
      model.toggleStep(0, 0);
      expect(notifyCount, greaterThan(0),
          reason: 'toggleStep should call notifyListeners so the grid redraws');
      expect(model.stepEnabled(0, 0), isTrue,
          reason: 'Step (0, 0) should be enabled after toggleStep');
    });

    test('toggling one step does not affect adjacent steps', () {
      model.toggleStep(0, 0);
      expect(model.stepEnabled(0, 1), isFalse,
          reason: 'Toggling step (0,0) must not affect step (0,1)');
      expect(model.stepEnabled(1, 0), isFalse,
          reason: 'Toggling step (0,0) must not affect step (1,0) on a different track');
    });
  });

  // -------------------------------------------------------------------------
  group('setStepVelocity', () {
    test('clamps a negative value to 0.0', () {
      model.setStepVelocity(0, 0, -0.5);
      expect(model.stepVelocity(0, 0), 0.0,
          reason: 'Negative velocity (-0.5) should clamp to 0.0 — silent');
    });

    test('clamps a value above 1.0 to 1.0', () {
      model.setStepVelocity(0, 0, 1.5);
      expect(model.stepVelocity(0, 0), 1.0,
          reason: 'Velocity above 1.0 (1.5) should clamp to 1.0 — maximum volume');
    });

    test('stores a valid mid-range value unchanged', () {
      model.setStepVelocity(0, 0, 0.5);
      expect(model.stepVelocity(0, 0), 0.5,
          reason: 'setStepVelocity(0, 0, 0.5) should store 0.5 — a valid velocity');
    });

    test('notifies listeners and updates velocity', () {
      int notifyCount = 0;
      model.addListener(() => notifyCount++);
      model.setStepVelocity(0, 0, 0.5);
      expect(notifyCount, greaterThan(0),
          reason: 'setStepVelocity should call notifyListeners so the pad indicator redraws');
      expect(model.stepVelocity(0, 0), 0.5,
          reason: 'Velocity for step (0,0) should be 0.5 after setStepVelocity(0, 0, 0.5)');
    });
  });

  // -------------------------------------------------------------------------
  group('hasNonDefaultStepSettings', () {
    test('returns false for a freshly constructed step', () {
      expect(model.hasNonDefaultStepSettings(0, 0), isFalse,
          reason: 'A new step has default velocity ($kDefaultStepVelocity) so hasNonDefaultStepSettings should be false');
    });

    test('returns true after setting a non-default velocity', () {
      model.setStepVelocity(0, 0, 0.5);
      expect(model.hasNonDefaultStepSettings(0, 0), isTrue,
          reason: 'Velocity 0.5 != $kDefaultStepVelocity so hasNonDefaultStepSettings should be true');
    });

    test('returns false after resetting velocity to the default', () {
      model.setStepVelocity(0, 0, 0.5);
      model.setStepVelocity(0, 0, kDefaultStepVelocity);
      expect(model.hasNonDefaultStepSettings(0, 0), isFalse,
          reason: 'Resetting velocity to kDefaultStepVelocity should make hasNonDefaultStepSettings return false again');
    });
  });

  // -------------------------------------------------------------------------
  group('clearAllSteps', () {
    test('disables all previously active steps across all tracks', () {
      model.toggleStep(0, 0);
      model.toggleStep(1, 5);
      model.toggleStep(2, 15);
      model.toggleStep(3, 8);

      model.clearAllSteps();

      for (int t = 0; t < kNumTracks; t++) {
        for (int s = 0; s < kNumSteps; s++) {
          expect(model.stepEnabled(t, s), isFalse,
              reason: 'clearAllSteps should disable step ($t, $s) — it was not cleared');
        }
      }
    });

    test('resets all step velocities to kDefaultStepVelocity', () {
      model.setStepVelocity(0, 0, 0.25);
      model.setStepVelocity(2, 7, 0.75);

      model.clearAllSteps();

      for (int t = 0; t < kNumTracks; t++) {
        for (int s = 0; s < kNumSteps; s++) {
          expect(model.stepVelocity(t, s), kDefaultStepVelocity,
              reason: 'clearAllSteps should reset velocity at ($t, $s) to $kDefaultStepVelocity');
        }
      }
    });

    test('notifies listeners and leaves all steps disabled', () {
      int notifyCount = 0;
      model.toggleStep(0, 0);
      model.addListener(() => notifyCount++);
      model.clearAllSteps();
      expect(notifyCount, greaterThan(0),
          reason: 'clearAllSteps should call notifyListeners so the grid redraws');
      expect(model.stepEnabled(0, 0), isFalse,
          reason: 'Step (0,0) should be disabled after clearAllSteps');
    });
  });

  // -------------------------------------------------------------------------
  group('saveError', () {
    test('is null initially', () {
      expect(model.saveError, isNull,
          reason: 'No save error should exist before any save attempt fails');
    });

    test('setSaveErrorForTest exposes the error via saveError getter', () {
      final err = Exception('storage full');
      model.setSaveErrorForTest(err);
      expect(model.saveError, err,
          reason: 'saveError must return the exact error passed to setSaveErrorForTest()');
    });

    test('setSaveErrorForTest calls notifyListeners', () {
      int notifyCount = 0;
      model.addListener(() => notifyCount++);
      model.setSaveErrorForTest(Exception('disk full'));
      expect(notifyCount, 1,
          reason: 'Setting a save error must call notifyListeners() so the UI can react');
    });

    test('clearSaveError resets saveError to null', () {
      model.setSaveErrorForTest(Exception('disk full'));
      model.clearSaveError();
      expect(model.saveError, isNull,
          reason: 'clearSaveError() must nullify the error so the UI does not re-show stale errors');
    });
  });

  // -------------------------------------------------------------------------
  group('stepDuration', () {
    test('is 125 000 µs at 120 BPM (16th notes)', () {
      model.setBpm(120);
      expect(model.stepDuration, const Duration(microseconds: 125000),
          reason: '60 000 000 µs / (120 BPM × 4 steps/beat) = 125 000 µs per step');
    });

    test('is 375 000 µs at 40 BPM', () {
      model.setBpm(40);
      expect(model.stepDuration, const Duration(microseconds: 375000),
          reason: '60 000 000 µs / (40 BPM × 4 steps/beat) = 375 000 µs per step');
    });

    test('is 50 000 µs at 300 BPM', () {
      model.setBpm(300);
      expect(model.stepDuration, const Duration(microseconds: 50000),
          reason: '60 000 000 µs / (300 BPM × 4 steps/beat) = 50 000 µs per step');
    });
  });
}
