import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/sequencer_model.dart';
import 'pad_config_sheet.dart';

/// A single pad button in the step grid.
/// Uses [context.select] so it only rebuilds when its own state changes.
/// Tap to toggle the step; long-press to open per-pad configuration.
class StepButton extends StatelessWidget {
  const StepButton({
    super.key,
    required this.trackIndex,
    required this.stepIndex,
  });

  final int trackIndex;
  final int stepIndex;

  void _showPadConfig(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanelColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) => ChangeNotifierProvider.value(
        value: context.read<SequencerModel>(),
        child: PadConfigSheet(trackIndex: trackIndex, stepIndex: stepIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isActive = context.select<SequencerModel, bool>(
      (m) => m.stepEnabled(trackIndex, stepIndex),
    );
    final isCurrent = context.select<SequencerModel, bool>(
      (m) => m.currentStep == stepIndex,
    );
    final hasNonDefault = context.select<SequencerModel, bool>(
      (m) => m.hasNonDefaultStepSettings(trackIndex, stepIndex),
    );
    final velocity = context.select<SequencerModel, double>(
      (m) => m.stepVelocity(trackIndex, stepIndex),
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
      onLongPress: () => _showPadConfig(context),
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
        child: hasNonDefault
            ? LayoutBuilder(
                builder: (_, constraints) {
                  final barHeight =
                      (constraints.maxHeight * velocity - 4).clamp(0.0, constraints.maxHeight - 4);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: 2,
                        bottom: 2,
                        width: 3,
                        height: barHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: isActive ? 0.75 : 0.45),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              )
            : null,
      ),
    );
  }
}
