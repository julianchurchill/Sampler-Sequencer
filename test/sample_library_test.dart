import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sampler_sequencer/audio/sample_library.dart';

void main() {
  late Directory tmpDir;
  late Directory libraryDir;
  late File indexFile;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('sample_library_test_');
    libraryDir = Directory('${tmpDir.path}/sampler_library');
    libraryDir.createSync(recursive: true);
    indexFile = File('${libraryDir.path}/index.json');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  /// Helper: create a dummy sample file in the library directory and return its path.
  String createSampleFile(String filename) {
    final file = File('${libraryDir.path}/$filename');
    file.writeAsBytesSync([0x52, 0x49, 0x46, 0x46]); // minimal bytes
    return file.path;
  }

  group('SampleLibrary.init() with injected directory', () {
    test('loads valid entries from index.json', () async {
      final samplePath = createSampleFile('kick.wav');
      indexFile.writeAsStringSync(jsonEncode([
        {'path': samplePath, 'name': 'Kick Drum'},
      ]));

      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      expect(lib.samples.length, 1,
          reason: 'A valid index.json with one entry should yield one sample');
      expect(lib.samples[0].name, 'Kick Drum',
          reason: 'The loaded sample name should match the index entry');
      expect(lib.samples[0].path, samplePath,
          reason: 'The loaded sample path should match the index entry');
    });

    test('skips entries where path is not a String', () async {
      final goodPath = createSampleFile('good.wav');
      indexFile.writeAsStringSync(jsonEncode([
        {'path': goodPath, 'name': 'Good'},
        {'path': 12345, 'name': 'Bad Path'},
      ]));

      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      expect(lib.samples.length, 1,
          reason: 'Entries with non-String path should be skipped');
      expect(lib.samples[0].name, 'Good',
          reason: 'Only the valid entry should be loaded');
    });

    test('skips entries where name is not a String', () async {
      final goodPath = createSampleFile('good.wav');
      final badPath = createSampleFile('bad.wav');
      indexFile.writeAsStringSync(jsonEncode([
        {'path': goodPath, 'name': 'Good'},
        {'path': badPath, 'name': 42},
      ]));

      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      expect(lib.samples.length, 1,
          reason: 'Entries with non-String name should be skipped');
      expect(lib.samples[0].name, 'Good',
          reason: 'Only the valid entry should be loaded');
    });

    test('skips entries with path traversal (.. segments)', () async {
      final goodPath = createSampleFile('good.wav');
      // Create an entry that tries to escape the library directory
      indexFile.writeAsStringSync(jsonEncode([
        {'path': goodPath, 'name': 'Good'},
        {'path': '${libraryDir.path}/../../../etc/passwd', 'name': 'Evil'},
      ]));

      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      expect(lib.samples.length, 1,
          reason: 'Entries with path traversal should be rejected');
      expect(lib.samples[0].name, 'Good',
          reason: 'Only the safe entry should be loaded');
    });

    test('skips entries pointing to non-existent files', () async {
      final goodPath = createSampleFile('exists.wav');
      indexFile.writeAsStringSync(jsonEncode([
        {'path': goodPath, 'name': 'Exists'},
        {'path': '${libraryDir.path}/ghost.wav', 'name': 'Ghost'},
      ]));

      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      expect(lib.samples.length, 1,
          reason: 'Entries pointing to non-existent files should be skipped');
      expect(lib.samples[0].name, 'Exists',
          reason: 'Only the entry with an existing file should be loaded');
    });

    test('handles malformed JSON (not a list) without crashing', () async {
      indexFile.writeAsStringSync('{"not": "a list"}');

      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      expect(lib.samples.isEmpty, true,
          reason:
              'Malformed JSON (object instead of list) should result in an empty library, not a crash');
    });

    test('handles empty list in index.json', () async {
      indexFile.writeAsStringSync(jsonEncode([]));

      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      expect(lib.samples.isEmpty, true,
          reason: 'An empty JSON list should produce an empty sample list');
    });

    test('skips entries that are not Map objects', () async {
      final goodPath = createSampleFile('good.wav');
      indexFile.writeAsStringSync(jsonEncode([
        {'path': goodPath, 'name': 'Good'},
        'just a string',
        42,
        null,
      ]));

      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      expect(lib.samples.length, 1,
          reason: 'Non-map entries in the list should be skipped');
      expect(lib.samples[0].name, 'Good',
          reason: 'Only valid map entries should be loaded');
    });
  });

  group('SampleLibrary.addRecording()', () {
    test('copies the file and adds an entry to the samples list', () async {
      // Initialise an empty library
      indexFile.writeAsStringSync(jsonEncode([]));
      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      // Create a "recorded" file outside the library directory
      final tempRecording = File('${tmpDir.path}/recording.m4a');
      tempRecording.writeAsBytesSync([0xDE, 0xAD, 0xBE, 0xEF]);

      await lib.addRecording(tempRecording.path, 'My Recording');

      expect(lib.samples.length, 1,
          reason: 'addRecording should add exactly one entry to the samples list');
      expect(lib.samples[0].name, 'My Recording',
          reason: 'The added entry should use the display name passed to addRecording');
      // The file should have been copied into the library directory
      expect(File(lib.samples[0].path).existsSync(), true,
          reason: 'addRecording should copy the file to the library directory');
      expect(lib.samples[0].path.startsWith(libraryDir.path), true,
          reason: 'The copied file path should be inside the library directory');
      // The original file should still exist (copy, not move)
      expect(tempRecording.existsSync(), true,
          reason: 'addRecording should copy, not move — the original file should still exist');
    });

    group('file extension extraction', () {
      Future<String> addAndGetPath(String tempFilename) async {
        indexFile.writeAsStringSync(jsonEncode([]));
        final lib = SampleLibrary(libraryDir: libraryDir);
        await lib.init();
        final tempFile = File('${tmpDir.path}/$tempFilename');
        tempFile.writeAsBytesSync([0xDE, 0xAD, 0xBE, 0xEF]);
        await lib.addRecording(tempFile.path, 'Test');
        return lib.samples[0].path;
      }

      test('preserves .wav extension from a .wav temp path', () async {
        final dest = await addAndGetPath('rec.wav');
        expect(dest.endsWith('.wav'), true,
            reason: '.wav temp file should be stored with .wav extension in the library');
      });

      test('preserves .m4a extension from a .m4a temp path', () async {
        final dest = await addAndGetPath('rec.m4a');
        expect(dest.endsWith('.m4a'), true,
            reason: '.m4a temp file should be stored with .m4a extension in the library');
      });

      test('preserves .mp3 extension from a .mp3 temp path', () async {
        final dest = await addAndGetPath('rec.mp3');
        expect(dest.endsWith('.mp3'), true,
            reason: '.mp3 temp file should be stored with .mp3 extension in the library');
      });

      test('falls back to m4a for a path with no extension', () async {
        final dest = await addAndGetPath('recording');
        expect(dest.endsWith('.m4a'), true,
            reason: 'A temp path with no extension should fall back to .m4a');
      });

      test('falls back to m4a for an unrecognised extension', () async {
        final dest = await addAndGetPath('rec.txt');
        expect(dest.endsWith('.m4a'), true,
            reason: 'An unrecognised extension (.txt) should fall back to .m4a, not be preserved');
      });

      test('uses only the last extension for a path with multiple dots', () async {
        final dest = await addAndGetPath('my.recording.2024.wav');
        expect(dest.endsWith('.wav'), true,
            reason: 'A path with multiple dots should use the last extension (.wav)');
      });

      test('is case-insensitive for extension matching', () async {
        final dest = await addAndGetPath('rec.WAV');
        expect(dest.endsWith('.WAV'), true,
            reason: 'Extension case should be preserved but matching should be case-insensitive');
      });
    });
  });

  group('SampleLibrary.rename()', () {
    test('updates the display name but not the file on disk', () async {
      final samplePath = createSampleFile('kick.wav');
      indexFile.writeAsStringSync(jsonEncode([
        {'path': samplePath, 'name': 'Kick Drum'},
      ]));

      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      final entry = lib.samples[0];
      final originalPath = entry.path;

      await lib.rename(entry, 'Bass Drum');

      expect(lib.samples[0].name, 'Bass Drum',
          reason: 'rename should update the display name in the samples list');
      expect(lib.samples[0].path, originalPath,
          reason: 'rename should not change the file path on disk');
      expect(File(originalPath).existsSync(), true,
          reason: 'The original file should still exist at its original path after rename');
    });
  });

  group('SampleLibrary.delete()', () {
    test('removes the file and the entry', () async {
      final samplePath = createSampleFile('kick.wav');
      indexFile.writeAsStringSync(jsonEncode([
        {'path': samplePath, 'name': 'Kick Drum'},
      ]));

      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      expect(lib.samples.length, 1,
          reason: 'Precondition: library should start with one entry');

      final entry = lib.samples[0];
      await lib.delete(entry);

      expect(lib.samples.isEmpty, true,
          reason: 'delete should remove the entry from the samples list');
      expect(File(samplePath).existsSync(), false,
          reason: 'delete should remove the actual file from disk');
    });
  });

  group('SampleLibrary._persistIndex() via _saveIndex()', () {
    test('writes valid JSON that can be re-loaded', () async {
      // Start with an empty library, add entries, then verify persisted JSON
      indexFile.writeAsStringSync(jsonEncode([]));
      final lib = SampleLibrary(libraryDir: libraryDir);
      await lib.init();

      // Create a temp file and add it as a recording
      final tempRecording = File('${tmpDir.path}/voice.m4a');
      tempRecording.writeAsBytesSync([0x01, 0x02, 0x03]);

      await lib.addRecording(tempRecording.path, 'Voice Sample');

      // Read the persisted index.json directly and verify it is valid JSON
      final rawJson = indexFile.readAsStringSync();
      final decoded = jsonDecode(rawJson);
      expect(decoded, isA<List>(),
          reason: 'Persisted index.json should be a JSON list');
      expect((decoded as List).length, 1,
          reason: 'Persisted index should contain exactly one entry after one addRecording');

      final entry = decoded[0] as Map<String, dynamic>;
      expect(entry['name'], 'Voice Sample',
          reason: 'Persisted entry name should match the display name passed to addRecording');
      expect(entry['path'], isA<String>(),
          reason: 'Persisted entry path should be a String');

      // Verify that a fresh SampleLibrary can re-load the index
      final lib2 = SampleLibrary(libraryDir: libraryDir);
      await lib2.init();
      expect(lib2.samples.length, 1,
          reason: 'A fresh SampleLibrary should reload the persisted index and get one entry');
      expect(lib2.samples[0].name, 'Voice Sample',
          reason: 'The reloaded entry name should match what was persisted');
    });
  });
}
