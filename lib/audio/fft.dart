import 'dart:math' as math;
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Cooley-Tukey radix-2 DIT FFT
//
// All functions operate in-place on parallel real/imaginary Float64Lists.
// The length of [re] and [im] must be equal and a positive power of 2.
// ---------------------------------------------------------------------------

/// Forward DFT (in-place). Transforms [re]/[im] from time to frequency domain.
void fft(Float64List re, Float64List im) => _transform(re, im, false);

/// Inverse DFT (in-place, with 1/N normalisation).
/// Transforms [re]/[im] from frequency to time domain.
void ifft(Float64List re, Float64List im) => _transform(re, im, true);

void _transform(Float64List re, Float64List im, bool inverse) {
  final n = re.length;
  assert(n == im.length && n > 0 && (n & (n - 1)) == 0,
      'FFT length must be a positive power of 2, got $n');

  // Bit-reversal permutation.
  int j = 0;
  for (int i = 1; i < n; i++) {
    int bit = n >> 1;
    while ((j & bit) != 0) {
      j ^= bit;
      bit >>= 1;
    }
    j ^= bit;
    if (i < j) {
      double t = re[i]; re[i] = re[j]; re[j] = t;
      t = im[i]; im[i] = im[j]; im[j] = t;
    }
  }

  // Butterfly stages.
  for (int len = 2; len <= n; len <<= 1) {
    final halfLen = len >> 1;
    final ang = math.pi / halfLen * (inverse ? 1.0 : -1.0);
    final wRe = math.cos(ang);
    final wIm = math.sin(ang);

    for (int i = 0; i < n; i += len) {
      double curRe = 1.0;
      double curIm = 0.0;
      for (int k = 0; k < halfLen; k++) {
        final uRe = re[i + k];
        final uIm = im[i + k];
        final vRe = re[i + k + halfLen] * curRe - im[i + k + halfLen] * curIm;
        final vIm = re[i + k + halfLen] * curIm + im[i + k + halfLen] * curRe;
        re[i + k] = uRe + vRe;
        im[i + k] = uIm + vIm;
        re[i + k + halfLen] = uRe - vRe;
        im[i + k + halfLen] = uIm - vIm;
        final nextRe = curRe * wRe - curIm * wIm;
        curIm = curRe * wIm + curIm * wRe;
        curRe = nextRe;
      }
    }
  }

  if (inverse) {
    final invN = 1.0 / n;
    for (int i = 0; i < n; i++) {
      re[i] *= invN;
      im[i] *= invN;
    }
  }
}
