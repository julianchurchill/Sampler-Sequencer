import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../constants.dart';
import '../models/sequencer_model.dart';

/// Bottom sheet that renders the current sequence to a WAV file and shares it.
class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key});

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  int _numLoops = 2;
  bool _exporting = false;
  List<int> _unsupportedTracks = [];

  static const _color = Color(0xFF66BB6A); // green accent for export

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _unsupportedTracks = [];
    });

    try {
      final tmpDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tmpDir.path}/export_$timestamp.wav';

      final unsupported = await context.read<SequencerModel>().exportWav(
        numLoops: _numLoops,
        outputPath: outputPath,
      );

      if (!mounted) return;
      setState(() {
        _unsupportedTracks = unsupported;
        _exporting = false;
      });

      // Share the file via the OS share sheet.
      await Share.shareXFiles(
        [XFile(outputPath, mimeType: 'audio/wav')],
        subject: 'Sampler Sequencer export',
      );
    } catch (e) {
      debugPrint('ExportSheet export error: $e');
      if (mounted) {
        setState(() => _exporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'EXPORT',
            style: TextStyle(
              color: _color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // ── Loop count ────────────────────────────────────────────────────
          const Text(
            'LOOPS',
            style: TextStyle(color: kTextDim, fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _CountButton(
                icon: Icons.remove,
                onTap: _exporting || _numLoops <= 1
                    ? null
                    : () => setState(() => _numLoops--),
              ),
              const SizedBox(width: 16),
              Text(
                '$_numLoops',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 16),
              _CountButton(
                icon: Icons.add,
                onTap: _exporting || _numLoops >= 16
                    ? null
                    : () => setState(() => _numLoops++),
              ),
              const SizedBox(width: 12),
              Text(
                _numLoops == 1 ? 'loop  (${_barDuration(context)} s)' : 'loops  (${_barDuration(context)} s)',
                style: const TextStyle(color: kTextDim, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Format label ─────────────────────────────────────────────────
          const Text(
            'FORMAT',
            style: TextStyle(color: kTextDim, fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'WAV  •  44100 Hz  •  16-bit stereo',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),

          // ── Unsupported-track warning ─────────────────────────────────────
          if (_unsupportedTracks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Track${_unsupportedTracks.length > 1 ? 's' : ''} '
                      '${_unsupportedTracks.map((t) => t + 1).join(', ')} '
                      '${_unsupportedTracks.length > 1 ? 'use' : 'uses'} '
                      'a non-WAV file and will be silent in the export.',
                      style: const TextStyle(color: Colors.orange, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── Progress bar ──────────────────────────────────────────────────
          if (_exporting) ...[
            LinearProgressIndicator(
              backgroundColor: _color.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(_color),
            ),
            const SizedBox(height: 16),
          ],

          // ── Export button ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.ios_share, size: 18),
              label: Text(_exporting ? 'Rendering…' : 'Export & Share'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _color,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _barDuration(BuildContext context) {
    final model = context.read<SequencerModel>();
    final secs = _numLoops * model.numSteps * 60.0 / (model.bpm * kStepsPerQuarterNote);
    return secs.toStringAsFixed(1);
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(
            color: onTap != null
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.1),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null ? Colors.white : Colors.white24,
        ),
      ),
    );
  }
}
