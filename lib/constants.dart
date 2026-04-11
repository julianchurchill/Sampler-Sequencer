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

// ---------------------------------------------------------------------------
// Time signature support
// ---------------------------------------------------------------------------

/// A time signature supported by the sequencer.
///
/// [numSteps] is computed as `numerator × (16 ÷ denominator)`, giving the
/// number of 16th-note steps in one bar.
///
/// [stepsPerGroup] controls how the pad grid draws visual beat separators:
/// - `/4` time  → 4 steps (one quarter note = 4 sixteenth notes)
/// - compound `/8` time → 6 steps (one dotted quarter = 6 sixteenth notes)
/// - irregular 7/8 → 2 steps (one eighth note = 2 sixteenth notes)
class SupportedTimeSignature {
  const SupportedTimeSignature(
    this.numerator,
    this.denominator,
    this.stepsPerGroup,
  );

  final int numerator;
  final int denominator;

  /// Number of pad steps per visual beat group in the grid.
  final int stepsPerGroup;

  /// Total 16th-note steps in one bar for this time signature.
  int get numSteps => numerator * (16 ~/ denominator);

  /// Display label, e.g. "4/4".
  String get label => '$numerator/$denominator';
}

const int kDefaultTimeSignatureNumerator = 4;
const int kDefaultTimeSignatureDenominator = 4;

/// All time signatures the user can select.
const List<SupportedTimeSignature> kSupportedTimeSignatures = [
  SupportedTimeSignature(2, 4, 4),  //  8 steps  (2 beats)
  SupportedTimeSignature(3, 4, 4),  // 12 steps  (3 beats)
  SupportedTimeSignature(4, 4, 4),  // 16 steps  (4 beats) — default
  SupportedTimeSignature(5, 4, 4),  // 20 steps  (5 beats)
  SupportedTimeSignature(6, 8, 6),  // 12 steps  (compound 2-feel)
  SupportedTimeSignature(7, 8, 2),  // 14 steps  (irregular)
  SupportedTimeSignature(9, 8, 6),  // 18 steps  (compound 3-feel)
  SupportedTimeSignature(12, 8, 6), // 24 steps  (compound 4-feel)
];

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
  const DrumPreset('Kick 808',  generateKick808),
  const DrumPreset('Kick Hard', generateKickHard),
  const DrumPreset('Snare',     generateSnare),
  const DrumPreset('Rim Shot',  generateRimShot),
  const DrumPreset('HH Closed', generateHiHatClosed),
  const DrumPreset('HH Open',   generateHiHatOpen),
  const DrumPreset('Clap',      generateClap),
  const DrumPreset('Tom',       generateTom),
  const DrumPreset('Cowbell',   generateCowbell),
];

/// Default preset index assigned to each track (0=Kick808, 2=Snare, 4=HH Closed, 5=HH Open).
const List<int> kDefaultPresetIndices = [0, 2, 4, 5];
