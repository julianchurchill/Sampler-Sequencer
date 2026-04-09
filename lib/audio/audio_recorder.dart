import 'package:record/record.dart';

/// Thin wrapper around the `record` package AudioRecorder.
///
/// Accepts an optional [recorder] for dependency injection in tests.
class AppAudioRecorder {
  AppAudioRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start(String path) => _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

  Future<String?> stop() => _recorder.stop();

  Future<void> dispose() => _recorder.dispose();
}
