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

    // Stub every AudioEngine getter/method that SequencerModel calls on
    // construction or in the methods under test.
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
    test('clamps below kMinBpm to kMinBpm', () {
      model.setBpm(0);
      expect(model.bpm, kMinBpm);
    });

    test('clamps above kMaxBpm to kMaxBpm', () {
      model.setBpm(9999);
      expect(model.bpm, kMaxBpm);
    });

    test('accepts a mid-range value', () {
      model.setBpm(140);
      expect(model.bpm, 140);
    });

    test('accepts exact boundary kMinBpm', () {
      model.setBpm(kMinBpm);
      expect(model.bpm, kMinBpm);
    });

    test('accepts exact boundary kMaxBpm', () {
      model.setBpm(kMaxBpm);
      expect(model.bpm, kMaxBpm);
    });

    test('notifies listeners', () {
      int notifyCount = 0;
      model.addListener(() => notifyCount++);
      model.setBpm(140);
      expect(notifyCount, greaterThan(0));
    });
  });

  // -------------------------------------------------------------------------
  group('toggleStep', () {
    test('inactive step becomes active', () {
      model.toggleStep(0, 0);
      expect(model.stepEnabled(0, 0), isTrue);
    });

    test('active step becomes inactive after second toggle', () {
      model.toggleStep(0, 0);
      model.toggleStep(0, 0);
      expect(model.stepEnabled(0, 0), isFalse);
    });

    test('notifies listeners', () {
      int notifyCount = 0;
      model.addListener(() => notifyCount++);
      model.toggleStep(0, 0);
      expect(notifyCount, greaterThan(0));
    });

    test('toggling one step does not affect others', () {
      model.toggleStep(0, 0);
      expect(model.stepEnabled(0, 1), isFalse);
      expect(model.stepEnabled(1, 0), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('setStepVelocity', () {
    test('clamps negative value to 0.0', () {
      model.setStepVelocity(0, 0, -0.5);
      expect(model.stepVelocity(0, 0), 0.0);
    });

    test('clamps value above 1.0 to 1.0', () {
      model.setStepVelocity(0, 0, 1.5);
      expect(model.stepVelocity(0, 0), 1.0);
    });

    test('stores a mid-range value', () {
      model.setStepVelocity(0, 0, 0.5);
      expect(model.stepVelocity(0, 0), 0.5);
    });

    test('notifies listeners', () {
      int notifyCount = 0;
      model.addListener(() => notifyCount++);
      model.setStepVelocity(0, 0, 0.5);
      expect(notifyCount, greaterThan(0));
    });
  });

  // -------------------------------------------------------------------------
  group('hasNonDefaultStepSettings', () {
    test('returns false for a fresh step', () {
      expect(model.hasNonDefaultStepSettings(0, 0), isFalse);
    });

    test('returns true after setting non-default velocity', () {
      model.setStepVelocity(0, 0, 0.5);
      expect(model.hasNonDefaultStepSettings(0, 0), isTrue);
    });

    test('returns false after resetting to default velocity', () {
      model.setStepVelocity(0, 0, 0.5);
      model.setStepVelocity(0, 0, kDefaultStepVelocity);
      expect(model.hasNonDefaultStepSettings(0, 0), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('clearAllSteps', () {
    test('disables all previously active steps', () {
      // Activate a spread of steps across tracks.
      model.toggleStep(0, 0);
      model.toggleStep(1, 5);
      model.toggleStep(2, 15);
      model.toggleStep(3, 8);

      model.clearAllSteps();

      for (int t = 0; t < kNumTracks; t++) {
        for (int s = 0; s < kNumSteps; s++) {
          expect(model.stepEnabled(t, s), isFalse,
              reason: 'track $t step $s should be disabled');
        }
      }
    });

    test('resets all velocities to kDefaultStepVelocity', () {
      model.setStepVelocity(0, 0, 0.25);
      model.setStepVelocity(2, 7, 0.75);

      model.clearAllSteps();

      for (int t = 0; t < kNumTracks; t++) {
        for (int s = 0; s < kNumSteps; s++) {
          expect(model.stepVelocity(t, s), kDefaultStepVelocity,
              reason: 'track $t step $s velocity should be default');
        }
      }
    });

    test('notifies listeners', () {
      int notifyCount = 0;
      model.addListener(() => notifyCount++);
      model.clearAllSteps();
      expect(notifyCount, greaterThan(0));
    });
  });

  // -------------------------------------------------------------------------
  group('stepDuration', () {
    test('is correct at 120 bpm (16th notes)', () {
      model.setBpm(120);
      // 60_000_000 µs / (120 bpm * 4 steps/beat) = 125_000 µs
      expect(model.stepDuration, const Duration(microseconds: 125000));
    });

    test('is correct at 40 bpm', () {
      model.setBpm(40);
      // 60_000_000 / (40 * 4) = 375_000 µs
      expect(model.stepDuration, const Duration(microseconds: 375000));
    });

    test('is correct at 300 bpm', () {
      model.setBpm(300);
      // 60_000_000 / (300 * 4) = 50_000 µs
      expect(model.stepDuration, const Duration(microseconds: 50000));
    });
  });
}
