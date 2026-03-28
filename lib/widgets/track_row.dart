import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final hasSample = context.select<SequencerModel, bool>(
      (m) => m.hasSample(trackIndex),
    );
    final sampleName = context.select<SequencerModel, String?>(
      (m) => m.sampleName(trackIndex),
    );
    final color = kTrackColors[trackIndex];
    final name = kTrackNames[trackIndex];

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
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _SmallButton(
                  label: 'LOAD',
                  color: color,
                  onTap: () =>
                      context.read<SequencerModel>().loadSample(trackIndex),
                ),
                if (hasSample) ...[
                  const SizedBox(width: 4),
                  _SmallButton(
                    label: '×',
                    color: kTextDim,
                    onTap: () =>
                        context.read<SequencerModel>().clearSample(trackIndex),
                  ),
                ],
              ],
            ),
            if (sampleName != null) ...[
              const SizedBox(height: 3),
              Text(
                sampleName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kTextDim,
                  fontSize: 8,
                ),
              ),
            ],
          ],
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
          // Extra gap between groups of 4 (visual beat grouping)
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
