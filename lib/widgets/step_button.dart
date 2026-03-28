import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/sequencer_model.dart';

/// A single pad button in the step grid.
/// Uses [context.select] so it only rebuilds when its own state changes.
class StepButton extends StatelessWidget {
  const StepButton({
    super.key,
    required this.trackIndex,
    required this.stepIndex,
  });

  final int trackIndex;
  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    final isActive = context.select<SequencerModel, bool>(
      (m) => m.stepEnabled(trackIndex, stepIndex),
    );
    final isCurrent = context.select<SequencerModel, bool>(
      (m) => m.currentStep == stepIndex,
    );

    final trackColor = kTrackColors[trackIndex];

    Color bgColor;
    Color? borderColor;

    if (isActive) {
      bgColor = isCurrent
          ? Color.lerp(trackColor, Colors.white, 0.35)!
          : trackColor;
      borderColor = isCurrent ? Colors.white : null;
    } else {
      bgColor = isCurrent ? kStepCurrentInactive : kStepInactive;
      borderColor = isCurrent ? Colors.white38 : null;
    }

    return GestureDetector(
      onTap: () => context.read<SequencerModel>().toggleStep(trackIndex, stepIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: borderColor != null
              ? Border.all(color: borderColor, width: 1.5)
              : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: trackColor.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
      ),
    );
  }
}
