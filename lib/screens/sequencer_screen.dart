import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants.dart';
import '../widgets/track_row.dart';
import '../widgets/transport_bar.dart';

/// Main screen: app bar + 4 track rows + transport bar.
class SequencerScreen extends StatefulWidget {
  const SequencerScreen({super.key});

  @override
  State<SequencerScreen> createState() => _SequencerScreenState();
}

class _SequencerScreenState extends State<SequencerScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('SAMPLER  SEQUENCER'),
            const SizedBox(width: 8),
            if (_version.isNotEmpty)
              Text(
                _version,
                style: const TextStyle(
                  fontSize: 10,
                  color: kTextDim,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
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
