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

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

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
    when(() => audio.setPreset(any(), any())).thenAnswer((_) async {});
    when(() => audio.clearCustomPath(any())).thenAnswer((_) async {});
    when(() => audio.setTrim(any(), any(), any())).thenReturn(null);
    when(() => audio.clearTrim(any())).thenReturn(null);
    when(() => audio.setTrackVolume(any(), any()))
        .thenAnswer((_) async {});
    when(() => audio.dispose()).thenAnswer((_) async {});

    model = SequencerModel(audio: audio);
  });

  tearDown(() async {
    model.dispose();
    // Flush pending microtasks (e.g. fire-and-forget _save() callbacks) before
    // resetting the mock, so stale callbacks don't hit a cleared stub table.
    await Future<void>.delayed(Duration.zero);
    reset(audio);
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
      void listener() => notifyCount++;
      model.addListener(listener);
      model.setBpm(140);
      expect(notifyCount, greaterThan(0),
          reason: 'setBpm should call notifyListeners so the UI can redraw');
      expect(model.bpm, 140,
          reason: 'bpm should be 140 after setBpm(140)');
      model.removeListener(listener);
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
      void listener() => notifyCount++;
      model.addListener(listener);
      model.toggleStep(0, 0);
      expect(notifyCount, greaterThan(0),
          reason: 'toggleStep should call notifyListeners so the grid redraws');
      expect(model.stepEnabled(0, 0), isTrue,
          reason: 'Step (0, 0) should be enabled after toggleStep');
      model.removeListener(listener);
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
      void listener() => notifyCount++;
      model.addListener(listener);
      model.setStepVelocity(0, 0, 0.5);
      expect(notifyCount, greaterThan(0),
          reason: 'setStepVelocity should call notifyListeners so the pad indicator redraws');
      expect(model.stepVelocity(0, 0), 0.5,
          reason: 'Velocity for step (0,0) should be 0.5 after setStepVelocity(0, 0, 0.5)');
      model.removeListener(listener);
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
      void listener() => notifyCount++;
      model.toggleStep(0, 0);
      model.addListener(listener);
      model.clearAllSteps();
      expect(notifyCount, greaterThan(0),
          reason: 'clearAllSteps should call notifyListeners so the grid redraws');
      expect(model.stepEnabled(0, 0), isFalse,
          reason: 'Step (0,0) should be disabled after clearAllSteps');
      model.removeListener(listener);
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

  // -------------------------------------------------------------------------
  group('toggleMute', () {
    test('delegates to audio engine setMuted with inverted current state', () {
      when(() => audio.isMuted(0)).thenReturn(false);
      model.toggleMute(0);
      verify(() => audio.setMuted(0, true)).called(1);
    });

    test('unmutes a currently muted track', () {
      when(() => audio.isMuted(1)).thenReturn(true);
      model.toggleMute(1);
      verify(() => audio.setMuted(1, false)).called(1);
    });

    test('notifies listeners after toggling mute', () {
      int notifyCount = 0;
      void listener() => notifyCount++;
      model.addListener(listener);
      when(() => audio.isMuted(0)).thenReturn(false);
      model.toggleMute(0);
      expect(notifyCount, greaterThan(0),
          reason: 'toggleMute should call notifyListeners so the UI updates the mute indicator');
      model.removeListener(listener);
    });
  });

  // -------------------------------------------------------------------------
  group('clearCustomSample', () {
    test('delegates to audio engine clearCustomPath', () {
      model.clearCustomSample(2);
      verify(() => audio.clearCustomPath(2)).called(1);
    });

    test('notifies listeners after clearing custom sample', () {
      int notifyCount = 0;
      void listener() => notifyCount++;
      model.addListener(listener);
      model.clearCustomSample(0);
      expect(notifyCount, greaterThan(0),
          reason: 'clearCustomSample should call notifyListeners so the track name updates');
      model.removeListener(listener);
    });
  });

  // -------------------------------------------------------------------------
  group('loadPreset', () {
    test('delegates to audio engine setPreset', () {
      model.loadPreset(1, 3);
      verify(() => audio.setPreset(1, 3)).called(1);
    });

    test('notifies listeners after loading preset', () {
      int notifyCount = 0;
      void listener() => notifyCount++;
      model.addListener(listener);
      model.loadPreset(0, 5);
      expect(notifyCount, greaterThan(0),
          reason: 'loadPreset should call notifyListeners so the track name and UI update');
      model.removeListener(listener);
    });
  });

  // -------------------------------------------------------------------------
  group('setTrim', () {
    test('delegates start and end to audio engine setTrim', () {
      const start = Duration(milliseconds: 100);
      const end = Duration(milliseconds: 500);
      model.setTrim(0, start, end);
      verify(() => audio.setTrim(0, start, end)).called(1);
    });

    test('delegates with null end to audio engine setTrim', () {
      const start = Duration(milliseconds: 200);
      model.setTrim(1, start, null);
      verify(() => audio.setTrim(1, start, null)).called(1);
    });

    test('notifies listeners after setting trim', () {
      int notifyCount = 0;
      void listener() => notifyCount++;
      model.addListener(listener);
      model.setTrim(0, Duration.zero, const Duration(milliseconds: 300));
      expect(notifyCount, greaterThan(0),
          reason: 'setTrim should call notifyListeners so the trim UI updates');
      model.removeListener(listener);
    });
  });

  // -------------------------------------------------------------------------
  group('clearTrim', () {
    test('delegates to audio engine clearTrim', () {
      model.clearTrim(3);
      verify(() => audio.clearTrim(3)).called(1);
    });

    test('notifies listeners after clearing trim', () {
      int notifyCount = 0;
      void listener() => notifyCount++;
      model.addListener(listener);
      model.clearTrim(0);
      expect(notifyCount, greaterThan(0),
          reason: 'clearTrim should call notifyListeners so the trim UI resets');
      model.removeListener(listener);
    });
  });

  // -------------------------------------------------------------------------
  group('setTrackVolume', () {
    test('delegates to audio engine setTrackVolume', () async {
      await model.setTrackVolume(2, 0.75);
      verify(() => audio.setTrackVolume(2, 0.75)).called(1);
    });

    test('notifies listeners after setting volume', () async {
      int notifyCount = 0;
      void listener() => notifyCount++;
      model.addListener(listener);
      await model.setTrackVolume(0, 0.5);
      expect(notifyCount, greaterThan(0),
          reason: 'setTrackVolume should call notifyListeners so the volume slider updates');
      model.removeListener(listener);
    });
  });

  // -------------------------------------------------------------------------
  group('_save error handling', () {
    test('does not throw an unhandled error when persistence fails', () async {
      // Make customPath throw to simulate a persistence failure inside the
      // fire-and-forget _save() callback.  Without a catchError handler this
      // would surface as an unhandled Future rejection and fail the test.
      when(() => audio.customPath(any()))
          .thenThrow(StateError('simulated persistence failure'));

      // setBpm triggers _save() internally.
      model.setBpm(100);

      // Flush microtasks so the fire-and-forget Future completes within the
      // test zone (which catches unhandled async errors).
      await Future<void>.delayed(Duration.zero);

      expect(model.bpm, 100,
          reason: '_save() failure should not prevent the BPM from being set');
    });
  });

  // -------------------------------------------------------------------------
  group('currentStepNotifier', () {
    test('starts at -1 (no playhead when sequencer is stopped)', () {
      expect(model.currentStepNotifier.value, -1,
          reason: 'currentStepNotifier should be -1 before playback starts — '
              'no step should be highlighted in the stopped state');
    });

    test('updates to the fired step when playback starts', () async {
      when(() => audio.isReady).thenReturn(true);
      when(() => audio.trigger(any(), velocity: any(named: 'velocity')))
          .thenAnswer((_) async {});
      when(() => audio.stopAll()).thenAnswer((_) async {});

      await model.togglePlay();

      expect(model.currentStepNotifier.value, 0,
          reason: '_fireAndAdvance() fires step 0 immediately on play; '
              'currentStepNotifier should reflect the step that just triggered '
              '(0), not the next internal counter value');
    });

    test('resets to -1 when playback stops', () async {
      when(() => audio.isReady).thenReturn(true);
      when(() => audio.trigger(any(), velocity: any(named: 'velocity')))
          .thenAnswer((_) async {});
      when(() => audio.stopAll()).thenAnswer((_) async {});

      await model.togglePlay(); // start
      await model.togglePlay(); // stop

      expect(model.currentStepNotifier.value, -1,
          reason: 'currentStepNotifier should return to -1 after stop so that '
              'no step remains highlighted in the UI when the sequencer is idle');
    });

    test('does not call notifyListeners during a tick — only currentStepNotifier updates', () async {
      when(() => audio.isReady).thenReturn(true);
      when(() => audio.trigger(any(), velocity: any(named: 'velocity')))
          .thenAnswer((_) async {});
      when(() => audio.stopAll()).thenAnswer((_) async {});

      // Start playback so the model is in a playing state.
      await model.togglePlay();

      // Register a model listener AFTER play() so we don't count that notification.
      int notifyCount = 0;
      void modelListener() => notifyCount++;
      model.addListener(modelListener);

      // Track currentStepNotifier separately.
      int notifierFires = 0;
      void notifierListener() => notifierFires++;
      model.currentStepNotifier.addListener(notifierListener);

      // Simulate a tick directly via the @visibleForTesting helper.
      model.fireAndAdvanceForTest();

      expect(notifyCount, 0,
          reason: 'A sequencer tick should NOT call notifyListeners() on the '
              'SequencerModel — only currentStepNotifier should update, so that '
              '62 unchanged StepButtons are not forced to re-evaluate their selectors');
      expect(notifierFires, 1,
          reason: 'currentStepNotifier should fire exactly once per tick to '
              'update the two StepButtons whose isCurrent state changed');

      model.removeListener(modelListener);
      model.currentStepNotifier.removeListener(notifierListener);
    });
  });
}
