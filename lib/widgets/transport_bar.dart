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
              const Text(
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

          // ---- Time signature (tappable) ----
          const _TimeSignatureDisplay(),

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

// ---------------------------------------------------------------------------

/// Tappable label showing the current step count and time signature.
/// Opens the time signature picker sheet on tap.
class _TimeSignatureDisplay extends StatelessWidget {
  const _TimeSignatureDisplay();

  @override
  Widget build(BuildContext context) {
    final numSteps = context.select<SequencerModel, int>((m) => m.numSteps);
    final timeSigLabel =
        context.select<SequencerModel, String>((m) => m.timeSignatureLabel);

    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$numSteps STEPS  •  $timeSigLabel',
            style: const TextStyle(
              color: kTextDim,
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'TAP TO CHANGE',
            style: TextStyle(
              color: Color(0xFF555555),
              fontSize: 7,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanelColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) => ChangeNotifierProvider.value(
        value: context.read<SequencerModel>(),
        child: const _TimeSignaturePicker(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Bottom sheet listing all supported time signatures for the user to choose.
class _TimeSignaturePicker extends StatelessWidget {
  const _TimeSignaturePicker();

  static const _color = Color(0xFF64B5F6); // blue accent for time sig

  @override
  Widget build(BuildContext context) {
    final currentNumerator = context.select<SequencerModel, int>(
      (m) => m.timeSignatureNumerator,
    );
    final currentDenominator = context.select<SequencerModel, int>(
      (m) => m.timeSignatureDenominator,
    );
    final model = context.read<SequencerModel>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TIME SIGNATURE',
            style: TextStyle(
              color: _color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          ...kSupportedTimeSignatures.map((sig) {
            final isSelected = sig.numerator == currentNumerator &&
                sig.denominator == currentDenominator;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              dense: true,
              onTap: () {
                model.setTimeSignature(sig.numerator, sig.denominator);
                Navigator.of(context).pop();
              },
              leading: Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? _color : kTextDim,
                size: 20,
              ),
              title: Text(
                sig.label,
                style: TextStyle(
                  color: isSelected ? Colors.white : kTextDim,
                  fontSize: 16,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                '${sig.numSteps} steps',
                style: const TextStyle(color: kTextDim, fontSize: 11),
              ),
            );
          }),
        ],
      ),
    );
  }
}
