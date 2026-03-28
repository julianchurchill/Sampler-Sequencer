import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SampleEntry {
  SampleEntry({required this.path, required this.name});
  String path;
  String name;
}

/// Persists user recordings to {documentsDir}/sampler_library/.
class SampleLibrary extends ChangeNotifier {
  final List<SampleEntry> _samples = [];
  List<SampleEntry> get samples => List.unmodifiable(_samples);

  Directory? _libraryDir;

  Future<void> init() async {
    final docsDir = await getApplicationDocumentsDirectory();
    _libraryDir = Directory('${docsDir.path}/sampler_library');
    await _libraryDir!.create(recursive: true);
    _reload();
  }

  void _reload() {
    if (_libraryDir == null) return;
    final files = _libraryDir!
        .listSync()
        .whereType<File>()
        .toList()
      ..sort((a, b) =>
          a.statSync().modified.compareTo(b.statSync().modified));
    _samples.clear();
    for (final file in files) {
      final filename = file.path.split('/').last;
      final name = filename.contains('.')
          ? filename.substring(0, filename.lastIndexOf('.'))
          : filename;
      _samples.add(SampleEntry(path: file.path, name: name));
    }
    notifyListeners();
  }

  /// Copy a finished recording into the library with [name] as the display name.
  Future<void> addRecording(String tempPath, String name) async {
    if (_libraryDir == null) return;
    final safeName = _sanitize(name);
    final ext = tempPath.contains('.') ? tempPath.split('.').last : 'm4a';
    final destPath = '${_libraryDir!.path}/$safeName.$ext';
    await File(tempPath).copy(destPath);
    _samples.add(SampleEntry(path: destPath, name: name));
    notifyListeners();
  }

  /// Rename a library entry (renames the file on disk).
  Future<void> rename(SampleEntry entry, String newName) async {
    final safeName = _sanitize(newName);
    final ext = entry.path.contains('.') ? entry.path.split('.').last : 'm4a';
    final dir = entry.path.substring(0, entry.path.lastIndexOf('/'));
    final newPath = '$dir/$safeName.$ext';
    await File(entry.path).rename(newPath);
    entry.path = newPath;
    entry.name = newName;
    notifyListeners();
  }

  Future<void> delete(SampleEntry entry) async {
    await File(entry.path).delete();
    _samples.remove(entry);
    notifyListeners();
  }

  String _sanitize(String name) => name
      .trim()
      .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
}
