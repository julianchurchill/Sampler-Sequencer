import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/sequencer_model.dart';

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

  // Normalised 0.0–1.0 values driven by the RangeSlider.
  double _startFrac = 0.0;
  double _endFrac = 1.0;

  @override
  void initState() {
    super.initState();
    _loadDuration();
  }

  @override
  void dispose() {
    // Stop any ongoing preview when the sheet closes.
    if (_previewing) {
      context.read<SequencerModel>().stopTrack(widget.trackIndex);
    }
    super.dispose();
  }

  Future<void> _loadDuration() async {
    final model = context.read<SequencerModel>();
    final dur = await model.getTrackDuration(widget.trackIndex);
    if (!mounted) return;
    setState(() {
      _duration = dur;
      _loading = false;
      if (dur != null && dur.inMilliseconds > 0) {
        final startMs = model.trimStart(widget.trackIndex).inMilliseconds;
        final endMs = model.trimEnd(widget.trackIndex)?.inMilliseconds ?? dur.inMilliseconds;
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

  Future<void> _togglePreview() async {
    final model = context.read<SequencerModel>();
    final dur = _duration;
    if (dur == null) return;

    if (_previewing) {
      await model.stopTrack(widget.trackIndex);
      if (mounted) setState(() => _previewing = false);
    } else {
      final startMs = (_startFrac * dur.inMilliseconds).round();
      final endMs = (_endFrac * dur.inMilliseconds).round();
      final start = Duration(milliseconds: startMs);
      final end = endMs < dur.inMilliseconds ? Duration(milliseconds: endMs) : null;

      setState(() => _previewing = true);
      await model.previewTrim(widget.trackIndex, start, end);

      // Auto-reset the button once playback finishes.
      if (mounted) setState(() => _previewing = false);
    }
  }

  void _applyTrim() {
    final model = context.read<SequencerModel>();
    final dur = _duration;
    if (dur == null) return;
    final startMs = (_startFrac * dur.inMilliseconds).round();
    final endMs = (_endFrac * dur.inMilliseconds).round();
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
                  if (_previewing) {
                    context.read<SequencerModel>().stopTrack(widget.trackIndex);
                    _previewing = false;
                  }
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
                  tooltip: _previewing ? 'Stop preview' : 'Preview trimmed sample',
                  color: color,
                  icon: Icon(
                    _previewing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
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
                    if (_previewing) {
                      context.read<SequencerModel>().stopTrack(widget.trackIndex);
                      _previewing = false;
                    }
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
