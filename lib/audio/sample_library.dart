import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SampleEntry {
  SampleEntry({required this.path, required this.name});
  String path;
  String name;
}

/// Persists user recordings to {documentsDir}/sampler_library/.
///
/// An index.json file in the library directory maps file paths to display
/// names, so names survive app restarts exactly as entered. Files use
/// timestamp-based names to avoid collisions.
class SampleLibrary extends ChangeNotifier {
  final List<SampleEntry> _samples = [];
  List<SampleEntry> get samples => List.unmodifiable(_samples);

  Directory? _libraryDir;
  File? _indexFile;

  Future<void> init() async {
    final docsDir = await getApplicationDocumentsDirectory();
    _libraryDir = Directory('${docsDir.path}/sampler_library');
    await _libraryDir!.create(recursive: true);
    _indexFile = File('${_libraryDir!.path}/index.json');
    await _loadIndex();
    notifyListeners();
  }

  Future<void> _loadIndex() async {
    _samples.clear();
    if (_indexFile != null && await _indexFile!.exists()) {
      try {
        final data = jsonDecode(await _indexFile!.readAsString()) as List<dynamic>;
        for (final item in data) {
          final path = item['path'] as String;
          final name = item['name'] as String;
          if (await File(path).exists()) {
            _samples.add(SampleEntry(path: path, name: name));
          }
        }
        return;
      } catch (e) {
        debugPrint('SampleLibrary index load error: $e');
      }
    }
    // No index or corrupted — migrate existing files, then write the index.
    _migrateFromFiles();
  }

  /// One-time migration: build the index from files already in the library
  /// directory (created before index.json was introduced).
  void _migrateFromFiles() {
    if (_libraryDir == null) return;
    final files = _libraryDir!
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('index.json'))
        .toList()
      ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    for (final file in files) {
      final filename = file.path.split('/').last;
      final stem = filename.contains('.')
          ? filename.substring(0, filename.lastIndexOf('.'))
          : filename;
      // Best-effort: convert underscores back to spaces for readability.
      _samples.add(SampleEntry(path: file.path, name: stem.replaceAll('_', ' ')));
    }
    _saveIndex();
  }

  Future<void> _saveIndex() async {
    if (_indexFile == null) return;
    try {
      final data = _samples.map((e) => {'path': e.path, 'name': e.name}).toList();
      await _indexFile!.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('SampleLibrary index save error: $e');
    }
  }

  /// Copy a finished recording into the library with [name] as the display name.
  Future<void> addRecording(String tempPath, String name) async {
    if (_libraryDir == null) return;
    final ext = tempPath.contains('.') ? tempPath.split('.').last : 'm4a';
    // Use a timestamp filename to avoid collisions regardless of display name.
    final filename = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final destPath = '${_libraryDir!.path}/$filename';
    await File(tempPath).copy(destPath);
    _samples.add(SampleEntry(path: destPath, name: name));
    await _saveIndex();
    notifyListeners();
  }

  /// Rename a library entry. Updates the index; does not rename the file.
  Future<void> rename(SampleEntry entry, String newName) async {
    entry.name = newName;
    await _saveIndex();
    notifyListeners();
  }

  Future<void> delete(SampleEntry entry) async {
    try {
      await File(entry.path).delete();
    } catch (e) {
      debugPrint('SampleLibrary delete error: $e');
    }
    _samples.remove(entry);
    await _saveIndex();
    notifyListeners();
  }
}
