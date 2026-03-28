import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/audio_engine.dart';
import '../constants.dart';
import '../models/sequencer_model.dart';
import 'step_button.dart';

/// One track row: label + load button on the left, 16 step pads on the right.
class TrackRow extends StatelessWidget {
  const TrackRow({super.key, required this.trackIndex});

  final int trackIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TrackLabel(trackIndex: trackIndex),
        const SizedBox(width: 4),
        Expanded(child: _StepRow(trackIndex: trackIndex)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _TrackLabel extends StatelessWidget {
  const _TrackLabel({required this.trackIndex});

  final int trackIndex;

  @override
  Widget build(BuildContext context) {
    final hasCustom = context.select<SequencerModel, bool>(
      (m) => m.hasCustomSample(trackIndex),
    );
    final name = context.select<SequencerModel, String>(
      (m) => m.trackName(trackIndex),
    );
    final color = kTrackColors[trackIndex];

    return SizedBox(
      width: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _SmallButton(
                  label: 'LOAD',
                  color: color,
                  onTap: () => _showSoundPicker(context),
                ),
                if (hasCustom) ...[
                  const SizedBox(width: 4),
                  _SmallButton(
                    label: '×',
                    color: kTextDim,
                    onTap: () =>
                        context.read<SequencerModel>().clearCustomSample(trackIndex),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSoundPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanelColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) => _SoundPickerSheet(
        trackIndex: trackIndex,
        model: context.read<SequencerModel>(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SoundPickerSheet extends StatelessWidget {
  const _SoundPickerSheet({required this.trackIndex, required this.model});

  final int trackIndex;
  final SequencerModel model;

  @override
  Widget build(BuildContext context) {
    final color = kTrackColors[trackIndex];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SELECT SOUND',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < kDrumPresets.length; i++)
                  _PresetChip(
                    label: kDrumPresets[i].name,
                    color: color,
                    onTap: () {
                      model.loadPreset(trackIndex, i);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFF2A2A2A)),
            TextButton.icon(
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Browse files…'),
              style: TextButton.styleFrom(
                foregroundColor: kTextDim,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              onPressed: () {
                Navigator.pop(context);
                model.loadCustomSample(trackIndex);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(4),
          color: color.withValues(alpha: 0.08),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StepRow extends StatelessWidget {
  const _StepRow({required this.trackIndex});

  final int trackIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int s = 0; s < kNumSteps; s++) ...[
          if (s > 0 && s % 4 == 0) const SizedBox(width: 4),
          Expanded(
            child: StepButton(
              trackIndex: trackIndex,
              stepIndex: s,
            ),
          ),
        ],
      ],
    );
  }
}
