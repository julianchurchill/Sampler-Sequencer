import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
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
  /// Optional injected library directory for testing. When null, [init] uses
  /// [getApplicationDocumentsDirectory] to resolve the default location.
  final Directory? _injectedLibraryDir;

  SampleLibrary({Directory? libraryDir}) : _injectedLibraryDir = libraryDir;

  final List<SampleEntry> _samples = [];
  List<SampleEntry> get samples => List.unmodifiable(_samples);

  Directory? _libraryDir;
  File? _indexFile;

  Future<void> init() async {
    if (_injectedLibraryDir != null) {
      _libraryDir = _injectedLibraryDir;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      _libraryDir = Directory('${docsDir.path}/sampler_library');
    }
    await _libraryDir!.create(recursive: true);
    _indexFile = File('${_libraryDir!.path}/index.json');
    await _loadIndex();
    notifyListeners();
  }

  /// Returns true if [filePath] is safely contained within the library
  /// directory. Rejects paths with `..` segments or those that resolve
  /// outside [_libraryDir].
  bool _isPathSafe(String filePath) {
    final canonicalLibDir = p.canonicalize(_libraryDir!.path);
    final canonicalFile = p.canonicalize(filePath);
    // The canonical path must start with the library directory path followed
    // by a separator (or be exactly equal, though that would be the dir itself).
    return canonicalFile.startsWith('$canonicalLibDir${p.separator}');
  }

  Future<void> _loadIndex() async {
    _samples.clear();
    if (_indexFile != null && await _indexFile!.exists()) {
      try {
        final decoded = jsonDecode(await _indexFile!.readAsString());
        if (decoded is! List<dynamic>) {
          debugPrint('SampleLibrary: index.json root is not a list, skipping');
          return;
        }
        for (final item in decoded) {
          if (item is! Map<String, dynamic>) continue;
          final rawPath = item['path'];
          final rawName = item['name'];
          if (rawPath is! String || rawName is! String) continue;
          if (!_isPathSafe(rawPath)) {
            debugPrint('SampleLibrary: rejected path outside library: $rawPath');
            continue;
          }
          if (await File(rawPath).exists()) {
            _samples.add(SampleEntry(path: rawPath, name: rawName));
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
