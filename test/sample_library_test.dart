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
}
