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
  });
}
