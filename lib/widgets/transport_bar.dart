import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/sequencer_model.dart';

/// Play/stop, BPM control, and clear-all button.
class TransportBar extends StatelessWidget {
  const TransportBar({super.key});

  @override
  Widget build(BuildContext context) {
    final isPlaying =
        context.select<SequencerModel, bool>((m) => m.isPlaying);
    final isLoading =
        context.select<SequencerModel, bool>((m) => m.isLoading);
    final bpm = context.select<SequencerModel, int>((m) => m.bpm);
    final model = context.read<SequencerModel>();

    return Container(
      height: 64,
      color: kPanelColor,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // ---- Play / Stop ----
          SizedBox(
            width: 52,
            height: 44,
            child: ElevatedButton(
              onPressed: isLoading ? null : model.togglePlay,
              style: ElevatedButton.styleFrom(
                backgroundColor: isPlaying
                    ? const Color(0xFFB71C1C)
                    : const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isPlaying ? Icons.stop : Icons.play_arrow,
                      size: 26,
                    ),
            ),
          ),

          const SizedBox(width: 16),

          // ---- BPM label ----
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BPM',
                style: TextStyle(
                  color: kTextDim,
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$bpm',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),

          // ---- BPM decrement / increment ----
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BpmButton(
                icon: Icons.keyboard_arrow_up,
                onTap: () => model.setBpm(bpm + 1),
                onLongPress: () => model.setBpm(bpm + 10),
              ),
              _BpmButton(
                icon: Icons.keyboard_arrow_down,
                onTap: () => model.setBpm(bpm - 1),
                onLongPress: () => model.setBpm(bpm - 10),
              ),
            ],
          ),

          const Spacer(),

          // ---- Step count label ----
          Text(
            '16 STEPS  •  4/4',
            style: TextStyle(
              color: kTextDim,
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),

          const Spacer(),

          // ---- Clear all steps ----
          TextButton(
            onPressed: model.clearAllSteps,
            style: TextButton.styleFrom(
              foregroundColor: kTextDim,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: const Text(
              'CLEAR',
              style: TextStyle(fontSize: 10, letterSpacing: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _BpmButton extends StatelessWidget {
  const _BpmButton({
    required this.icon,
    required this.onTap,
    required this.onLongPress,
  });

  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Icon(icon, color: Colors.white70, size: 20),
    );
  }
}
