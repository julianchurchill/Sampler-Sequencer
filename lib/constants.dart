import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'audio/dsp_utils.dart';

const int kNumTracks = 4;
const int kNumSteps = 16;
const int kDefaultBpm = 120;
const int kMinBpm = 40;
const int kMaxBpm = 300;

// Each step maps to 1 internal sequencer beat.
// To make steps behave as 16th notes at the user's displayed BPM,
// the internal tempo is set to displayBpm * 4.
const double kStepsPerQuarterNote = 4.0;

// endBeat for the Sequence equals the number of steps.
const double kSequenceEndBeat = kNumSteps + 0.0;

const List<String> kTrackNames = ['KICK', 'SNARE', 'HH CLO', 'HH OPEN'];

const List<Color> kTrackColors = [
  Color(0xFFFF5722), // deep orange — kick
  Color(0xFF00BCD4), // cyan — snare
  Color(0xFFFFCA28), // amber — closed hi-hat
  Color(0xFFCE93D8), // light purple — open hi-hat
];

// Dimmed (inactive step) versions — 30% opacity baked in as hex.
const List<Color> kTrackColorsDim = [
  Color(0x4DFF5722),
  Color(0x4D00BCD4),
  Color(0x4DFFCA28),
  Color(0x4DCE93D8),
];

const Color kBgColor = Color(0xFF0A0A0A);
const Color kPanelColor = Color(0xFF161616);
const Color kStepInactive = Color(0xFF2D2D2D);
const Color kStepCurrentInactive = Color(0xFF3D3D3D);
const Color kTextDim = Color(0xFF888888);
const Color kTextBright = Colors.white;
const Color kAccentColor = Color(0xFFFF5722);

const double kDefaultStepVelocity = 1.0;

// ---------------------------------------------------------------------------
// Preset catalogue
// ---------------------------------------------------------------------------

typedef SampleGenerator = Float64List Function(int sr);

class DrumPreset {
  const DrumPreset(this.name, this.generator);
  final String name;
  final SampleGenerator generator;
}

final List<DrumPreset> kDrumPresets = [
  DrumPreset('Kick 808',  generateKick808),
  DrumPreset('Kick Hard', generateKickHard),
  DrumPreset('Snare',     generateSnare),
  DrumPreset('Rim Shot',  generateRimShot),
  DrumPreset('HH Closed', generateHiHatClosed),
  DrumPreset('HH Open',   generateHiHatOpen),
  DrumPreset('Clap',      generateClap),
  DrumPreset('Tom',       generateTom),
  DrumPreset('Cowbell',   generateCowbell),
];

/// Default preset index assigned to each track (0=Kick808, 2=Snare, 4=HH Closed, 5=HH Open).
const List<int> kDefaultPresetIndices = [0, 2, 4, 5];
