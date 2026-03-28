import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../audio/audio_engine.dart';
import '../audio/audio_recorder.dart';
import '../audio/sample_library.dart';
import '../constants.dart';
import '../models/sequencer_model.dart';
import 'step_button.dart';
import 'trim_editor_sheet.dart';

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
    final name = context.select<SequencerModel, String>(
      (m) => m.trackName(trackIndex),
    );
    final hasCustom = context.select<SequencerModel, bool>(
      (m) => m.hasCustomSample(trackIndex),
    );
    final hasTrim = context.select<SequencerModel, bool>(
      (m) => m.hasTrim(trackIndex),
    );
    final color = kTrackColors[trackIndex];
    // Tint the settings button in the track colour when any customisation is active.
    final buttonColor = (hasCustom || hasTrim) ? color : kTextDim;

    return SizedBox(
      width: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _showSettings(context),
              child: Icon(Icons.tune, size: 18, color: buttonColor),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanelColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: context.read<SequencerModel>()),
          ChangeNotifierProvider.value(value: context.read<SampleLibrary>()),
        ],
        child: _TrackSettingsSheet(trackIndex: trackIndex),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Track settings sheet  (volume + sound + trim in one place)
// ---------------------------------------------------------------------------

class _TrackSettingsSheet extends StatelessWidget {
  const _TrackSettingsSheet({required this.trackIndex});
  final int trackIndex;

  void _openSoundPicker(BuildContext context) {
    Navigator.pop(context); // close settings first
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanelColor,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) => MultiProvider(
        providers: [
          Provider.value(value: context.read<SequencerModel>()),
          ChangeNotifierProvider.value(value: context.read<SampleLibrary>()),
        ],
        child: _SoundPickerSheet(trackIndex: trackIndex),
      ),
    );
  }

  void _openTrimEditor(BuildContext context) {
    Navigator.pop(context); // close settings first
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanelColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) => Provider.value(
        value: context.read<SequencerModel>(),
        child: TrimEditorSheet(trackIndex: trackIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = kTrackColors[trackIndex];
    final model = context.watch<SequencerModel>();
    final volume = model.trackVolume(trackIndex);
    final hasCustom = model.hasCustomSample(trackIndex);
    final hasTrim = model.hasTrim(trackIndex);
    final soundName = model.trackName(trackIndex);

    String trimLabel = 'No trim';
    if (hasTrim) {
      final s = model.trimStart(trackIndex);
      final e = model.trimEnd(trackIndex);
      String fmt(Duration d) {
        final ms = d.inMilliseconds;
        return '${ms ~/ 1000}.${((ms % 1000) ~/ 10).toString().padLeft(2, '0')}s';
      }
      trimLabel = e != null ? '${fmt(s)} – ${fmt(e)}' : '${fmt(s)} – end';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            model.trackName(trackIndex).toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // ── Volume ──────────────────────────────────────────────────
          const _SectionLabel(label: 'VOLUME'),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.volume_down, size: 16, color: kTextDim),
              Expanded(
                child: SliderTheme(
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
                    value: volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) =>
                        context.read<SequencerModel>().setTrackVolume(trackIndex, v),
                  ),
                ),
              ),
              const Icon(Icons.volume_up, size: 16, color: kTextDim),
            ],
          ),
          const SizedBox(height: 20),

          // ── Sound ────────────────────────────────────────────────────
          const _SectionLabel(label: 'SOUND'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  soundName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              _SmallButton(
                label: 'CHANGE',
                color: color,
                onTap: () => _openSoundPicker(context),
              ),
              if (hasCustom) ...[
                const SizedBox(width: 6),
                _SmallButton(
                  label: '×',
                  color: kTextDim,
                  onTap: () => context.read<SequencerModel>().clearCustomSample(trackIndex),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // ── Trim ─────────────────────────────────────────────────────
          const _SectionLabel(label: 'TRIM'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  trimLabel,
                  style: TextStyle(
                    color: hasTrim ? Colors.white : kTextDim,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SmallButton(
                label: 'EDIT',
                color: hasTrim ? color : kTextDim,
                onTap: () => _openTrimEditor(context),
              ),
              if (hasTrim) ...[
                const SizedBox(width: 6),
                _SmallButton(
                  label: '×',
                  color: kTextDim,
                  onTap: () => context.read<SequencerModel>().clearTrim(trackIndex),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sound picker sheet
// ---------------------------------------------------------------------------

enum _RecordState { idle, recording }

class _SoundPickerSheet extends StatefulWidget {
  const _SoundPickerSheet({required this.trackIndex});
  final int trackIndex;

  @override
  State<_SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends State<_SoundPickerSheet> {
  _RecordState _recordState = _RecordState.idle;
  final _recorder = AppAudioRecorder();
  String? _tempPath;
  final _nameController = TextEditingController();

  @override
  void dispose() {
    if (_recordState == _RecordState.recording) {
      _recorder.stop(); // discard if sheet closed mid-recording
    }
    _recorder.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }
    final tmp = await getTemporaryDirectory();
    final path =
        '${tmp.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(path);
    if (mounted) setState(() => _recordState = _RecordState.recording);
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (mounted) setState(() => _recordState = _RecordState.idle);
    if (path != null) {
      _tempPath = path;
      _promptForName();
    }
  }

  void _promptForName() {
    final library = context.read<SampleLibrary>();
    _nameController.text = 'Recording ${library.samples.length + 1}';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('Name sample'),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Sample name',
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: kTextDim),
            ),
          ),
          onSubmitted: (_) => _saveRecording(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _tempPath = null;
              Navigator.pop(ctx);
            },
            child: const Text('DISCARD', style: TextStyle(color: kTextDim)),
          ),
          TextButton(
            onPressed: () => _saveRecording(ctx),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRecording(BuildContext dialogCtx) async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _tempPath == null) return;
    Navigator.pop(dialogCtx);
    await context.read<SampleLibrary>().addRecording(_tempPath!, name);
    _tempPath = null;
  }

  void _promptRename(BuildContext ctx, SampleEntry entry) {
    _nameController.text = entry.name;
    showDialog<void>(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('Rename sample'),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: kTextDim),
            ),
          ),
          onSubmitted: (_) => _commitRename(dlgCtx, entry),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('CANCEL', style: TextStyle(color: kTextDim)),
          ),
          TextButton(
            onPressed: () => _commitRename(dlgCtx, entry),
            child: const Text('RENAME'),
          ),
        ],
      ),
    );
  }

  Future<void> _commitRename(BuildContext dlgCtx, SampleEntry entry) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(dlgCtx);
    await context.read<SampleLibrary>().rename(entry, name);
  }

  @override
  Widget build(BuildContext context) {
    final color = kTrackColors[widget.trackIndex];
    final model = context.read<SequencerModel>();
    final library = context.watch<SampleLibrary>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Title ----
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

          // ---- Built-in presets ----
          _SectionLabel(label: 'PRESETS'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < kDrumPresets.length; i++)
                _PresetChip(
                  label: kDrumPresets[i].name,
                  color: color,
                  onTap: () {
                    model.loadPreset(widget.trackIndex, i);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- My samples ----
          Row(
            children: [
              const Expanded(child: _SectionLabel(label: 'MY SAMPLES')),
              if (_recordState == _RecordState.idle)
                _SmallButton(
                  label: '⏺  RECORD',
                  color: const Color(0xFFEF5350),
                  onTap: _startRecording,
                )
              else
                _SmallButton(
                  label: '⏹  STOP',
                  color: const Color(0xFFEF5350),
                  onTap: _stopRecording,
                ),
            ],
          ),
          if (_recordState == _RecordState.recording) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                _RecordingIndicator(),
                SizedBox(width: 6),
                Text('Recording…',
                    style: TextStyle(color: Color(0xFFEF5350), fontSize: 11)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          if (library.samples.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No recordings yet. Tap ⏺ RECORD to capture a sample.',
                style: const TextStyle(color: kTextDim, fontSize: 10),
              ),
            )
          else
            for (final entry in library.samples)
              _LibrarySampleRow(
                entry: entry,
                color: color,
                onLoad: () {
                  model.loadCustomSample2(widget.trackIndex, entry.path, entry.name);
                  Navigator.pop(context);
                },
                onRename: () => _promptRename(context, entry),
                onDelete: () => context.read<SampleLibrary>().delete(entry),
              ),

          const Divider(height: 24, color: Color(0xFF2A2A2A)),

          // ---- Browse files ----
          TextButton.icon(
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: const Text('Browse files…'),
            style: TextButton.styleFrom(
              foregroundColor: kTextDim,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            onPressed: () {
              Navigator.pop(context);
              model.loadCustomSample(widget.trackIndex);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: kTextDim,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _LibrarySampleRow extends StatelessWidget {
  const _LibrarySampleRow({
    required this.entry,
    required this.color,
    required this.onLoad,
    required this.onRename,
    required this.onDelete,
  });

  final SampleEntry entry;
  final Color color;
  final VoidCallback onLoad;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(label: 'LOAD', color: color, onTap: onLoad),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRename,
            child: const Icon(Icons.edit_outlined, size: 16, color: kTextDim),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.delete_outline, size: 16, color: kTextDim),
          ),
        ],
      ),
    );
  }
}

class _RecordingIndicator extends StatefulWidget {
  const _RecordingIndicator();

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFEF5350),
          shape: BoxShape.circle,
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
