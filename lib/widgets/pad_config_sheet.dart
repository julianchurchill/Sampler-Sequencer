import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/sequencer_model.dart';

/// Bottom sheet for configuring per-pad settings (currently velocity) for a
/// single step. Changes are applied live as the slider moves.
class PadConfigSheet extends StatelessWidget {
  const PadConfigSheet({
    super.key,
    required this.trackIndex,
    required this.stepIndex,
  });

  final int trackIndex;
  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<SequencerModel>();
    final color = kTrackColors[trackIndex];
    final velocity = model.stepVelocity(trackIndex, stepIndex);
    final isDefault = !model.hasNonDefaultStepSettings(trackIndex, stepIndex);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'PAD ${stepIndex + 1}',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // Velocity
          Row(
            children: [
              const Text(
                'VELOCITY',
                style: TextStyle(
                  color: kTextDim,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                '${(velocity * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              thumbColor: color,
              activeTrackColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.25),
              overlayColor: color.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: velocity,
              min: 0.0,
              max: 1.0,
              onChanged: (v) =>
                  context.read<SequencerModel>().setStepVelocity(trackIndex, stepIndex, v),
            ),
          ),
          const SizedBox(height: 16),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: isDefault
                    ? null
                    : () => context.read<SequencerModel>().setStepVelocity(
                          trackIndex,
                          stepIndex,
                          kDefaultStepVelocity,
                        ),
                child: Text(
                  'RESET',
                  style: TextStyle(
                    color: isDefault ? kTextDim.withValues(alpha: 0.35) : kTextDim,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('DONE'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
