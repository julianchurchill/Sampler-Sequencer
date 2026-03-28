import 'package:flutter/material.dart';

import '../constants.dart';
import '../widgets/track_row.dart';
import '../widgets/transport_bar.dart';

/// Main screen: app bar + 4 track rows + transport bar.
class SequencerScreen extends StatelessWidget {
  const SequencerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        title: const Text('SAMPLER  SEQUENCER'),
        toolbarHeight: 36,
      ),
      body: Column(
        children: [
          // ---- Step grid ----
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
              child: Column(
                children: [
                  for (int t = 0; t < kNumTracks; t++) ...[
                    Expanded(child: TrackRow(trackIndex: t)),
                    if (t < kNumTracks - 1)
                      const Divider(height: 1, color: Color(0xFF1E1E1E)),
                  ],
                ],
              ),
            ),
          ),
          // ---- Transport ----
          const TransportBar(),
        ],
      ),
    );
  }
}
