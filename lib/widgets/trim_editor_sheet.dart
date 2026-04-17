import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/dsp_utils.dart';
import '../audio/wav_io.dart';
import '../constants.dart';
import '../models/sequencer_model.dart';

/// Number of amplitude bins computed from the PCM data for waveform display.
/// 400 bins gives sub-pixel resolution on most phone screens without excessive
/// computation time during load.
const int _kWaveformBins = 400;

/// Bottom sheet for non-destructive trim of the sample assigned to [trackIndex].
/// Presents a RangeSlider over the full sample duration and shows the selected
/// start / end times. A play button previews the trimmed region live.
class TrimEditorSheet extends StatefulWidget {
  const TrimEditorSheet({super.key, required this.trackIndex});

  final int trackIndex;

  @override
  State<TrimEditorSheet> createState() => _TrimEditorSheetState();
}

class _TrimEditorSheetState extends State<TrimEditorSheet> {
  Duration? _duration;
  bool _loading = true;
  bool _previewing = false;
  double _playProgress = 0.0;
  StreamSubscription<Duration>? _positionSub;
  Timer? _previewTimer;

  // Normalised 0.0–1.0 values driven by the RangeSlider.
  double _startFrac = 0.0;
  double _endFrac = 1.0;

  // Waveform peak bins — null until PCM has been read.
  Float64List? _waveformPeaks;

  @override
  void initState() {
    super.initState();
    _loadDuration();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _previewTimer?.cancel();
    // Stop any ongoing preview when the sheet closes.
    if (_previewing) {
      context.read<SequencerModel>().stopTrack(widget.trackIndex);
    }
    super.dispose();
  }

  Future<void> _loadDuration() async {
    final model = context.read<SequencerModel>();
    final path = model.samplePath(widget.trackIndex);
    final results = await Future.wait([
      model.getTrackDuration(widget.trackIndex),
      readWav(path),
    ]);
    if (!mounted) return;

    final dur = results[0] as Duration?;
    final wavData = results[1] as WavData?;

    setState(() {
      _duration = dur;
      _loading = false;
      if (wavData != null) {
        _waveformPeaks = extractWaveformPeaks(
            wavData.samples, wavData.numChannels, _kWaveformBins);
      }
      if (dur != null && dur.inMilliseconds > 0) {
        final startMs = model.trimStart(widget.trackIndex).inMilliseconds;
        final endMs =
            model.trimEnd(widget.trackIndex)?.inMilliseconds ?? dur.inMilliseconds;
        _startFrac = (startMs / dur.inMilliseconds).clamp(0.0, 1.0);
        _endFrac = (endMs / dur.inMilliseconds).clamp(0.0, 1.0);
      }
    });
  }

  String _fmt(Duration d) {
    final ms = d.inMilliseconds;
    final s = ms ~/ 1000;
    final frac = (ms % 1000) ~/ 10;
    return '${s.toString().padLeft(1, '0')}.${frac.toString().padLeft(2, '0')}s';
  }

  void _stopPreview() {
    _positionSub?.cancel();
    _positionSub = null;
    _previewTimer?.cancel();
    _previewTimer = null;
    context.read<SequencerModel>().stopTrack(widget.trackIndex);
    if (mounted) setState(() { _previewing = false; _playProgress = 0.0; });
  }

  /// Returns the effective trim-end in milliseconds.
  ///
  /// If [endFrac] maps to a position before the sample end it is used as-is;
  /// otherwise the full sample duration is used (i.e. "play to end").
  int _effectiveEndMs(double endFrac, Duration dur) {
    final endMs = (endFrac * dur.inMilliseconds).round();
    return endMs < dur.inMilliseconds ? endMs : dur.inMilliseconds;
  }

  Future<void> _togglePreview() async {
    final dur = _duration;
    if (dur == null) return;

    if (_previewing) {
      _stopPreview();
      return;
    }

    final model = context.read<SequencerModel>();
    final startMs = (_startFrac * dur.inMilliseconds).round();
    final endMs = (_endFrac * dur.inMilliseconds).round();
    final start = Duration(milliseconds: startMs);
    final end = endMs < dur.inMilliseconds ? Duration(milliseconds: endMs) : null;
    final effectiveEndMs = _effectiveEndMs(_endFrac, dur);
    final trimDurationMs = effectiveEndMs - startMs;

    setState(() { _previewing = true; _playProgress = 0.0; });

    // Subscribe to position updates for the waveform playhead.
    _positionSub?.cancel();
    _positionSub = model.positionStream.listen((pos) {
      if (!mounted || trimDurationMs <= 0) return;
      final progress = (pos.inMilliseconds - startMs) / trimDurationMs;
      setState(() => _playProgress = progress.clamp(0.0, 1.0));
    });

    // Auto-reset after the trim duration — previewTrim returns as soon as
    // audio setup completes, not when playback finishes.
    _previewTimer?.cancel();
    _previewTimer = Timer(Duration(milliseconds: trimDurationMs), () {
      _positionSub?.cancel();
      _positionSub = null;
      _previewTimer = null;
      if (mounted) setState(() { _previewing = false; _playProgress = 0.0; });
    });

    await model.previewTrim(widget.trackIndex, start, end);
  }

  void _applyTrim() {
    final model = context.read<SequencerModel>();
    final dur = _duration;
    if (dur == null) return;
    final startMs = (_startFrac * dur.inMilliseconds).round();
    final endMs = _effectiveEndMs(_endFrac, dur);
    final isFullRange = startMs <= 0 && endMs >= dur.inMilliseconds;
    if (isFullRange) {
      model.clearTrim(widget.trackIndex);
    } else {
      model.setTrim(
        widget.trackIndex,
        Duration(milliseconds: startMs),
        endMs < dur.inMilliseconds ? Duration(milliseconds: endMs) : null,
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final color = kTrackColors[widget.trackIndex];
    final dur = _duration;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRIM SAMPLE',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),

          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (dur == null || dur.inMilliseconds == 0)
            const Text(
              'Unable to read sample duration.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          else ...[
            // Waveform display
            SizedBox(
              height: 80,
              child: CustomPaint(
                painter: _WaveformPainter(
                  peaks: _waveformPeaks ?? Float64List(0),
                  startFrac: _startFrac,
                  endFrac: _endFrac,
                  playheadFrac: _previewing
                      ? _startFrac + _playProgress * (_endFrac - _startFrac)
                      : null,
                  color: color,
                ),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 8),

            // Time labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Start: ${_fmt(Duration(milliseconds: (_startFrac * dur.inMilliseconds).round()))}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Text(
                  'End: ${_fmt(Duration(milliseconds: (_endFrac * dur.inMilliseconds).round()))}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Range slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                rangeThumbShape: const RoundRangeSliderThumbShape(
                  enabledThumbRadius: 8,
                ),
                activeTrackColor: color,
                inactiveTrackColor: color.withValues(alpha: 0.2),
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.15),
              ),
              child: RangeSlider(
                values: RangeValues(_startFrac, _endFrac),
                onChanged: (v) {
                  // Stop any active preview when the user adjusts the range.
                  if (_previewing) _stopPreview();
                  setState(() {
                    _startFrac = v.start;
                    _endFrac = v.end;
                  });
                },
              ),
            ),

            // Total duration label + preview button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: ${_fmt(dur)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                IconButton(
                  onPressed: _togglePreview,
                  tooltip: _previewing ? 'Pause preview' : 'Preview trimmed sample',
                  color: color,
                  icon: Icon(
                    _previewing ? Icons.pause_circle_outline : Icons.play_circle_outline,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    if (_previewing) _stopPreview();
                    setState(() {
                      _startFrac = 0.0;
                      _endFrac = 1.0;
                    });
                  },
                  child: const Text('RESET', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _applyTrim,
                  child: const Text('APPLY'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.peaks,
    required this.startFrac,
    required this.endFrac,
    required this.color,
    this.playheadFrac,
  });

  final Float64List peaks;
  final double startFrac;
  final double endFrac;
  final Color color;
  final double? playheadFrac;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || size.width <= 0 || size.height <= 0) return;
    final midY = size.height / 2;
    final binWidth = size.width / peaks.length;

    for (int i = 0; i < peaks.length; i++) {
      final x = (i + 0.5) * binWidth;
      final frac = i / peaks.length;
      final isActive = frac >= startFrac && frac < endFrac;
      final h = (peaks[i] * midY).clamp(1.0, midY);
      canvas.drawLine(
        Offset(x, midY - h),
        Offset(x, midY + h),
        Paint()
          ..color = isActive
              ? color.withValues(alpha: 0.85)
              : color.withValues(alpha: 0.2)
          ..strokeWidth = binWidth.clamp(1.0, 3.0)
          ..strokeCap = StrokeCap.round,
      );
    }

    if (playheadFrac != null) {
      final x = (playheadFrac! * size.width).clamp(0.0, size.width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      peaks != old.peaks ||
      startFrac != old.startFrac ||
      endFrac != old.endFrac ||
      playheadFrac != old.playheadFrac ||
      color != old.color;
}
