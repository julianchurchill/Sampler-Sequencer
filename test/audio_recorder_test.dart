import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:sampler_sequencer/audio/audio_recorder.dart';

class MockAudioRecorder extends Mock implements AudioRecorder {}

void main() {
  late MockAudioRecorder mockRecorder;
  late AppAudioRecorder sut;

  setUpAll(() {
    // Register fallback value for RecordConfig (needed by mocktail for any()).
    registerFallbackValue(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100, numChannels: 1),
    );
  });

  setUp(() {
    mockRecorder = MockAudioRecorder();
    sut = AppAudioRecorder(recorder: mockRecorder);
  });

  tearDown(() {
    reset(mockRecorder);
  });

  group('AppAudioRecorder', () {
    test('hasPermission() delegates to the underlying AudioRecorder', () async {
      when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);

      final result = await sut.hasPermission();

      expect(result, true,
          reason: 'hasPermission() must return the value from the underlying recorder');
      verify(() => mockRecorder.hasPermission()).called(1);
    });

    test('start() calls the underlying AudioRecorder with WAV config at 44100 Hz mono', () async {
      when(() => mockRecorder.start(any(), path: any(named: 'path')))
          .thenAnswer((_) async {});

      await sut.start('/tmp/recording.wav');

      final captured = verify(
        () => mockRecorder.start(
          captureAny(),
          path: captureAny(named: 'path'),
        ),
      ).captured;

      final config = captured[0] as RecordConfig;
      expect(config.encoder, AudioEncoder.wav,
          reason: 'Recordings must use WAV encoder to produce uncompressed audio for the library');
      expect(config.sampleRate, 44100,
          reason: 'Sample rate must be 44100 Hz to match the exporter and preset sample rate');
      expect(config.numChannels, 1,
          reason: 'Mono recording reduces file size; mixing to stereo happens in the exporter');
      expect(captured[1], '/tmp/recording.wav',
          reason: 'start() must forward the caller-supplied path to the underlying recorder');
    });

    test('stop() delegates to the underlying AudioRecorder and returns its path', () async {
      when(() => mockRecorder.stop()).thenAnswer((_) async => '/tmp/recording.wav');

      final result = await sut.stop();

      expect(result, '/tmp/recording.wav',
          reason: 'stop() must return the path returned by the underlying recorder');
      verify(() => mockRecorder.stop()).called(1);
    });

    test('stop() returns null when the underlying recorder returns null', () async {
      when(() => mockRecorder.stop()).thenAnswer((_) async => null);

      final result = await sut.stop();

      expect(result, isNull,
          reason: 'stop() must propagate null from the underlying recorder (indicates nothing was recorded)');
    });

    test('dispose() delegates to the underlying AudioRecorder', () async {
      when(() => mockRecorder.dispose()).thenAnswer((_) async {});

      await sut.dispose();

      verify(() => mockRecorder.dispose()).called(1);
    });
  });
}
