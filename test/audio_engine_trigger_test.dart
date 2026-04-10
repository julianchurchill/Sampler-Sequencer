import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:sampler_sequencer/audio/audio_engine.dart';

// ---------------------------------------------------------------------------
// Mocktail infrastructure
// ---------------------------------------------------------------------------

class MockAudioPlayer extends Mock implements AudioPlayer {}

/// Fallback value for [Source]-typed arguments in any() / captureAny() matchers.
class _FakeSource extends Fake implements Source {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns a [MockAudioPlayer] with every method called during
/// [AudioEngine.trigger]'s fast (untrimmed, lowLatency) path stubbed to
/// complete immediately. Calls are tracked via [stopCount] / [playCount] maps
/// that the caller provides.
MockAudioPlayer _makePlayer(
  Map<MockAudioPlayer, int> stopCounts,
  Map<MockAudioPlayer, int> playCounts,
  Map<MockAudioPlayer, List<double>> playVolumes,
) {
  final p = MockAudioPlayer();
  stopCounts[p] = 0;
  playCounts[p] = 0;
  playVolumes[p] = [];

  when(() => p.stop()).thenAnswer((_) async {
    stopCounts[p] = stopCounts[p]! + 1;
  });
  when(() => p.play(any(), volume: any(named: 'volume'))).thenAnswer((inv) async {
    playCounts[p] = playCounts[p]! + 1;
    final vol = inv.namedArguments[#volume] as double?;
    if (vol != null) playVolumes[p]!.add(vol);
  });

  // Stubs needed only during initForTest path (no-ops are fine).
  when(() => p.setSource(any())).thenAnswer((_) async {});
  when(() => p.setVolume(any())).thenAnswer((_) async {});
  when(() => p.dispose()).thenAnswer((_) async {});
  return p;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSource());
  });

  group('AudioEngine trigger path (fast/untrimmed/lowLatency)', () {
    late AudioEngine engine;

    /// Tracking maps populated by [_makePlayer].
    late Map<MockAudioPlayer, int> stopCounts;
    late Map<MockAudioPlayer, int> playCounts;
    late Map<MockAudioPlayer, List<double>> playVolumes;

    /// All 4 × slotsPerTrack sequencer players, in engine order.
    late List<MockAudioPlayer> allPlayers;

    /// Convenience view of the 6 players owned by track 0.
    late List<MockAudioPlayer> track0Players;

    setUp(() {
      stopCounts = {};
      playCounts = {};
      playVolumes = {};

      engine = AudioEngine();

      allPlayers = [
        for (int i = 0; i < 4 * AudioEngine.slotsPerTrack; i++)
          _makePlayer(stopCounts, playCounts, playVolumes),
      ];
      track0Players =
          allPlayers.sublist(0, AudioEngine.slotsPerTrack);

      // Preview player: only onPositionChanged is accessed outside trigger().
      final preview = MockAudioPlayer();
      when(() => preview.onPositionChanged)
          .thenAnswer((_) => const Stream.empty());

      engine.initForTest(players: allPlayers, previewPlayer: preview);
    });

    // -----------------------------------------------------------------------
    test(
      'all 16 consecutive trigger() calls fire play() — '
      'no beats silently dropped',
      () async {
        // This is the primary regression guard for the 3/16-kicks bug.
        // Each trigger uses a different ping-pong slot (cycling 0..slotsPerTrack-1).
        // After 16 triggers the total play() count across all track-0 players
        // must equal 16. Any value below 16 means beats are being silently
        // dropped — caused by a generation check or unexpected await in the
        // fast path racing with a concurrent trigger.
        for (int i = 0; i < 16; i++) {
          await engine.trigger(0);
        }

        final totalPlays = track0Players
            .map((p) => playCounts[p]!)
            .reduce((a, b) => a + b);

        expect(totalPlays, 16,
            reason: 'Every trigger() call must reach play(). '
                'total=$totalPlays means ${16 - totalPlays} beat(s) were '
                'silently dropped. Check for a generation guard or unexpected '
                'await in the untrimmed fast path of trigger().');
      },
    );

    // -----------------------------------------------------------------------
    test(
      'ping-pong: each slot is stopped and played exactly once in '
      '${AudioEngine.slotsPerTrack} triggers',
      () async {
        // Fire exactly slotsPerTrack triggers so every slot is visited once.
        // Verifies the round-robin advance and that no slot is skipped or
        // double-fired.
        for (int i = 0; i < AudioEngine.slotsPerTrack; i++) {
          await engine.trigger(0);
        }

        for (int s = 0; s < AudioEngine.slotsPerTrack; s++) {
          final p = track0Players[s];
          expect(stopCounts[p], 1,
              reason: 'slot $s: stop() should be called exactly once '
                  'in ${AudioEngine.slotsPerTrack} triggers, '
                  'got ${stopCounts[p]}');
          expect(playCounts[p], 1,
              reason: 'slot $s: play() should be called exactly once '
                  'in ${AudioEngine.slotsPerTrack} triggers, '
                  'got ${playCounts[p]}');
        }
      },
    );

    // -----------------------------------------------------------------------
    test(
      'muted track fires no play() calls',
      () async {
        engine.setMuted(0, true);

        for (int i = 0; i < 16; i++) {
          await engine.trigger(0);
        }

        final totalPlays = track0Players
            .map((p) => playCounts[p]!)
            .reduce((a, b) => a + b);

        expect(totalPlays, 0,
            reason: 'Muted track must not call play() on any slot. '
                'Got $totalPlays call(s).');
      },
    );

    // -----------------------------------------------------------------------
    test(
      'velocity is multiplied by track volume and passed to play()',
      () async {
        // Default track volume is 1.0; velocity 0.5 → effective volume 0.5.
        await engine.trigger(0, velocity: 0.5);

        // Exactly one slot (slot 0, the first in the round-robin) is used.
        final allVolumes = track0Players
            .expand((p) => playVolumes[p]!)
            .toList();

        expect(allVolumes, hasLength(1),
            reason: 'Exactly one play() call should have been made '
                'for a single trigger()');
        expect(allVolumes.first, closeTo(0.5, 1e-9),
            reason: 'play() volume should equal velocity (0.5) × '
                'track volume (1.0) = 0.5, got ${allVolumes.first}');
      },
    );

    // -----------------------------------------------------------------------
    test(
      'sample reload loads slot 0 before slot 1 starts — '
      'prevents soundId null race on Android SoundPool',
      () async {
        // Root-cause regression: when _reloadSourceForTrack() ran all slots in
        // parallel, slots 1-5 read slot 0's soundId from Android's urlToPlayers
        // before the async soundPool.load() coroutine had posted it back to the
        // main thread.  They copied null, so SoundPoolPlayer.start() skipped
        // soundPool.play() silently — only triggers landing on slot 0 produced
        // sound (~3 of 16 steps at 120 BPM).  The fix loads slot 0 first
        // (sequential await), then slots 1-N in parallel.
        final events = <String>[];
        final slot0Completer = Completer<void>();

        // Slot 0: blocks until explicitly released (simulates SoundPool's async
        // soundPool.load() posting back to the Android main thread).
        when(() => track0Players[0].setSource(any())).thenAnswer((_) async {
          events.add('slot0_started');
          await slot0Completer.future;
          events.add('slot0_completed');
        });

        // Slot 1: records when its setSource begins.
        when(() => track0Players[1].setSource(any())).thenAnswer((_) async {
          events.add('slot1_started');
        });

        // Fire a sample change without awaiting — mirrors the UI behaviour.
        engine.setPreset(0, 1);

        // Without yielding to the event loop, slot 0 has started (the mock
        // body ran synchronously up to its first await), but slot 1 must NOT
        // have started yet: the reload must await slot 0 before launching any
        // subsequent slot.
        expect(events, equals(['slot0_started']),
            reason: 'Only slot 0 should have started at this point. '
                'If slot 1 is already in events, the reload is parallel — '
                'that is the race that leaves slots 1-5 with a null soundId '
                'on Android, causing ~3/16 steps to fire silently. '
                'events=$events');

        // Release slot 0, then let the Dart event loop process continuations.
        slot0Completer.complete();
        await Future<void>.delayed(Duration.zero);

        expect(events.indexOf('slot0_completed'),
            lessThan(events.indexOf('slot1_started')),
            reason: 'slot 0 must fully complete before slot 1 starts. '
                'events=$events');
      },
    );

    // -----------------------------------------------------------------------
    test(
      'trigger() during an in-flight source reload awaits the reload '
      'before calling play() — regression for non-deterministic sample playback',
      () async {
        // Record the order in which async operations complete so we can assert
        // that play() is never called before setSource() finishes.
        final events = <String>[];

        // Block every track-0 setSource() behind a completer to simulate the
        // latency of SoundPool loading a new sample from disk.  Without the
        // fix, trigger() calls play() immediately, while setSource() is still
        // in-flight — SoundPool silently drops the hit (stream-id 0).
        final loadCompleter = Completer<void>();
        for (final p in track0Players) {
          when(() => p.setSource(any())).thenAnswer((_) async {
            await loadCompleter.future;
            events.add('setSource_completed');
          });
        }

        // Override play() on slot 0 (the first slot in the round-robin) to
        // record when it is actually invoked relative to the setSource calls.
        when(
          () => track0Players[0].play(any(), volume: any(named: 'volume')),
        ).thenAnswer((_) async {
          events.add('play');
        });

        // Change the sample without awaiting — matches what loadPreset() and
        // loadCustomSample() do in the UI today.
        engine.setPreset(0, 1);

        // Fire a trigger immediately — before any setSource() has completed.
        final triggerFuture = engine.trigger(0);

        // Release the SoundPool load barrier, then await the trigger.
        loadCompleter.complete();
        await triggerFuture;

        // play() must appear AFTER every setSource_completed event.
        // If play() appears first, the sample wasn't loaded yet and SoundPool
        // would have silently dropped the hit on real hardware.
        final playIdx = events.indexOf('play');
        final lastSetSourceIdx = events.lastIndexOf('setSource_completed');

        expect(playIdx, greaterThan(lastSetSourceIdx),
            reason: 'play() must not fire until all '
                '${AudioEngine.slotsPerTrack} setSource() calls for the new '
                'sample have completed.  events=$events  '
                'playIdx=$playIdx  lastSetSourceIdx=$lastSetSourceIdx');
      },
    );
  });
}
