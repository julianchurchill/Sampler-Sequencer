import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/sequencer_model.dart';
import '../widgets/export_sheet.dart';
import '../widgets/track_row.dart';
import '../widgets/transport_bar.dart';

// Build timestamp injected at compile time via --dart-define=BUILD_TIMESTAMP=...
// Falls back to 'dev' for local debug builds.
const String _kBuildTimestamp = String.fromEnvironment(
  'BUILD_TIMESTAMP',
  defaultValue: 'dev',
);

/// Main screen: app bar + 4 track rows + transport bar.
class SequencerScreen extends StatefulWidget {
  const SequencerScreen({super.key});

  @override
  State<SequencerScreen> createState() => _SequencerScreenState();
}

class _SequencerScreenState extends State<SequencerScreen> {
  PackageInfo? _packageInfo;
  SequencerModel? _model;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newModel = context.read<SequencerModel>();
    if (_model != newModel) {
      _model?.removeListener(_onModelChanged);
      _model = newModel;
      _model!.addListener(_onModelChanged);
    }
  }

  void _onModelChanged() {
    final err = _model?.saveError;
    if (err == null) return;
    _model!.clearSaveError();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kPanelColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text(
            'SAVE ERROR',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: Colors.red,
            ),
          ),
          content: Text(
            '$err',
            style: const TextStyle(fontSize: 12, color: kTextBright),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(color: kAccentColor)),
            ),
          ],
        ),
      );
    });
  }

  @override
  void dispose() {
    _model?.removeListener(_onModelChanged);
    super.dispose();
  }

  void _showVersionInfo(BuildContext context) {
    final info = _packageInfo;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanelColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'SAMPLER  SEQUENCER',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: kTextBright,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info != null) ...[
              _InfoRow(label: 'Version', value: 'v${info.version}'),
              _InfoRow(label: 'Build', value: info.buildNumber),
            ],
            const _InfoRow(label: 'Built', value: _kBuildTimestamp),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: kAccentColor)),
          ),
        ],
      ),
    );
  }

  void _showExport(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanelColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) => Provider.value(
        value: context.read<SequencerModel>(),
        child: const ExportSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        title: const Text('SAMPLER  SEQUENCER'),
        toolbarHeight: 36,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 18),
            tooltip: 'Version info',
            color: kTextDim,
            onPressed: () => _showVersionInfo(context),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share, size: 20),
            tooltip: 'Export',
            color: kTextDim,
            onPressed: () => _showExport(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
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
      ),
    );
  }
}

/// A single label/value row used inside the version info dialog.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: kTextDim),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 11, color: kTextBright),
          ),
        ],
      ),
    );
  }
}
