import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Shared WAV I/O primitives
//
// Used by both dsp_utils.dart (drum preset synthesis) and audio_exporter.dart
// (offline mix export) so that WAV header format knowledge lives in one place.
// ---------------------------------------------------------------------------

/// Decoded PCM data from a WAV file.
class WavData {
  WavData({
    required this.sampleRate,
    required this.numChannels,
    required this.samples,
  });

  final int sampleRate;
  final int numChannels;

  /// Raw 16-bit signed PCM samples, interleaved for stereo.
  final Int16List samples;

  int get numFrames => samples.length ~/ numChannels;
}

/// Build a 44-byte WAV header for 16-bit PCM data.
///
/// [numSamples] is the total number of sample values (frames × channels).
Uint8List writeWavHeader({
  required int numSamples,
  required int sampleRate,
  required int numChannels,
}) {
  final dataSize = numSamples * numChannels * 2;
  final hdr = ByteData(44);

  void setFourCC(int offset, String s) {
    for (int i = 0; i < 4; i++) {
      hdr.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  setFourCC(0, 'RIFF');
  hdr.setUint32(4, 36 + dataSize, Endian.little);
  setFourCC(8, 'WAVE');
  setFourCC(12, 'fmt ');
  hdr.setUint32(16, 16, Endian.little);        // fmt chunk size
  hdr.setUint16(20, 1, Endian.little);         // PCM
  hdr.setUint16(22, numChannels, Endian.little);
  hdr.setUint32(24, sampleRate, Endian.little);
  hdr.setUint32(28, sampleRate * numChannels * 2, Endian.little); // byte rate
  hdr.setUint16(32, numChannels * 2, Endian.little);              // block align
  hdr.setUint16(34, 16, Endian.little);        // bits per sample
  setFourCC(36, 'data');
  hdr.setUint32(40, dataSize, Endian.little);

  return hdr.buffer.asUint8List();
}

/// Convert a sub-range of a Float64List mix buffer to little-endian Int16 bytes.
///
/// Returns a Uint8List of length (end - start) * 2.
/// Both Android and iOS are little-endian, matching the WAV spec, so we can
/// write the Int16List backing buffer directly without per-sample setInt16.
Uint8List pcmChunkToBytes(Float64List buf, int start, int end, double scale) {
  final count = end - start;
  final pcm = Int16List(count);
  for (int i = 0; i < count; i++) {
    pcm[i] = (buf[start + i] * scale * 32767).round().clamp(-32768, 32767);
  }
  return pcm.buffer.asUint8List();
}

/// Write a WAV file in chunks, avoiding holding both Float64List and full
/// Int16List simultaneously.
///
/// Instead of allocating a full Int16List copy of the mix buffer, this streams
/// the PCM conversion in chunks of [_kChunkSamples] samples, keeping peak
/// memory close to the Float64List size alone.
Future<void> writeWavChunked({
  required String outputPath,
  required Float64List mixBuffer,
  required double scale,
  required int sampleRate,
  required int numChannels,
}) async {
  const chunkSamples = 8192;
  final totalSamples = mixBuffer.length;
  final numFrames = totalSamples ~/ numChannels;

  final header = writeWavHeader(
    numSamples: numFrames,
    sampleRate: sampleRate,
    numChannels: numChannels,
  );

  final file = File(outputPath);
  final sink = file.openWrite();
  sink.add(header);

  for (int offset = 0; offset < totalSamples; offset += chunkSamples) {
    final end = (offset + chunkSamples).clamp(0, totalSamples);
    sink.add(pcmChunkToBytes(mixBuffer, offset, end, scale));
  }

  await sink.close();
}

/// Read the duration of a WAV file without loading the full PCM data.
///
/// Only the first 512 bytes are read to locate the RIFF/WAVE header chunks.
/// The duration is derived from the `byteRate` field in the `fmt ` chunk and
/// the `data` chunk size. Falls back to a file-size estimate when the `data`
/// chunk is not found within the first 512 bytes (e.g. files with large
/// embedded metadata blocks).
/// Returns null if the file is missing, corrupt, or not PCM format.
Future<Duration?> readWavDuration(String path) async {
  try {
    final file = File(path);
    final fileLen = await file.length();
    final readLen = fileLen.clamp(0, 512);
    final raf = await file.open();
    final buf = await raf.read(readLen);
    await raf.close();
    if (buf.length < 44) return null;

    String fourCC(int off) => String.fromCharCodes(buf, off, off + 4);
    if (fourCC(0) != 'RIFF' || fourCC(8) != 'WAVE') return null;

    int? byteRate, dataSize;
    int i = 12;

    while (i + 8 <= buf.length) {
      final chunkId = fourCC(i);
      final chunkSize =
          ByteData.sublistView(buf, i + 4, i + 8).getUint32(0, Endian.little);

      if (chunkId == 'fmt ' && i + 20 <= buf.length) {
        final fmt = ByteData.sublistView(buf, i + 8, i + 20);
        if (fmt.getUint16(0, Endian.little) != 1) return null; // not PCM
        byteRate = fmt.getUint32(8, Endian.little);
      } else if (chunkId == 'data') {
        dataSize = chunkSize;
        break;
      }

      if (chunkSize == 0) break; // malformed chunk; avoid infinite loop
      i += 8 + chunkSize + (chunkSize & 1);
    }

    if (byteRate == null || byteRate == 0) return null;
    final effectiveBytes = dataSize ?? (fileLen - 44).clamp(0, fileLen);
    if (effectiveBytes <= 0) return null;
    return Duration(microseconds: effectiveBytes * 1000000 ~/ byteRate);
  } catch (e) {
    debugPrint('readWavDuration error: $e');
    return null;
  }
}

/// Parse a WAV file into PCM frames.
/// Returns null if the file is missing, not a WAV, or not PCM format.
Future<WavData?> readWav(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 44) return null;

    String asString(List<int> b) => String.fromCharCodes(b);
    if (asString(bytes.sublist(0, 4)) != 'RIFF') return null;
    if (asString(bytes.sublist(8, 12)) != 'WAVE') return null;

    int? audioFormat, numChannels, sampleRate, bitsPerSample;
    int? dataOffset, dataSize;

    int i = 12;
    while (i + 8 <= bytes.length) {
      final chunkId = asString(bytes.sublist(i, i + 4));
      final bd = ByteData.sublistView(bytes, i + 4, i + 8);
      final chunkSize = bd.getUint32(0, Endian.little);

      if (chunkId == 'fmt ') {
        final fmt = ByteData.sublistView(bytes, i + 8, i + 8 + chunkSize);
        audioFormat = fmt.getUint16(0, Endian.little);
        numChannels = fmt.getUint16(2, Endian.little);
        sampleRate = fmt.getUint32(4, Endian.little);
        bitsPerSample = fmt.getUint16(14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = i + 8;
        dataSize = chunkSize;
        break; // data chunk found; stop walking
      }

      // Chunks are word-aligned.
      i += 8 + chunkSize + (chunkSize & 1);
    }

    if (audioFormat != 1) return null; // must be PCM
    if (numChannels == null || sampleRate == null || bitsPerSample == null) return null;
    if (dataOffset == null || dataSize == null) return null;

    final clampedSize = dataSize.clamp(0, bytes.length - dataOffset);
    final bytesPerSample = bitsPerSample ~/ 8;
    final numSamples = clampedSize ~/ bytesPerSample;
    final out = Int16List(numSamples);
    final view = ByteData.sublistView(bytes, dataOffset, dataOffset + clampedSize);

    if (bitsPerSample == 16) {
      for (int j = 0; j < numSamples; j++) {
        out[j] = view.getInt16(j * 2, Endian.little);
      }
    } else if (bitsPerSample == 8) {
      // 8-bit WAV is unsigned; convert to signed 16-bit.
      for (int j = 0; j < numSamples; j++) {
        out[j] = ((view.getUint8(j) - 128) << 8).clamp(-32768, 32767);
      }
    } else {
      return null; // unsupported bit depth
    }

    return WavData(
      sampleRate: sampleRate,
      numChannels: numChannels,
      samples: out,
    );
  } catch (e) {
    debugPrint('readWav error: $e');
    return null;
  }
}
