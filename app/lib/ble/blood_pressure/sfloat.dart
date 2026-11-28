/// IEEE-11073 16-bit SFLOAT used by the Blood Pressure Measurement characteristic.
class Sfloat {
  const Sfloat._();

  static const int nan = 0x07ff;
  static const int nres = 0x0800;
  static const int positiveInfinity = 0x07fe;
  static const int negativeInfinity = 0x0802;
  static const int reserved = 0x0801;

  /// Decodes one SFLOAT word. Special values return null, except infinities.
  static double? decode(int raw) {
    final word = raw & 0xffff;
    switch (word) {
      case nan:
      case nres:
      case reserved:
        return null;
      case positiveInfinity:
        return double.infinity;
      case negativeInfinity:
        return double.negativeInfinity;
    }
    var mantissa = word & 0x0fff;
    if (mantissa >= 0x0800) {
      mantissa -= 0x1000;
    }
    var exponent = (word >> 12) & 0x0f;
    if (exponent >= 0x08) {
      exponent -= 0x10;
    }
    return mantissa * _pow10(exponent);
  }

  static int encode({required int mantissa, required int exponent}) {
    var m = mantissa;
    var e = exponent;
    if (m < -2048 || m > 2047 || e < -8 || e > 7) {
      throw ArgumentError('sfloat mantissa/exponent out of range');
    }
    if (m < 0) {
      m += 0x1000;
    }
    if (e < 0) {
      e += 0x10;
    }
    return ((e & 0x0f) << 12) | (m & 0x0fff);
  }

  static double _pow10(int exponent) {
    var value = 1.0;
    final times = exponent.abs();
    for (var i = 0; i < times; i++) {
      value *= 10;
    }
    return exponent >= 0 ? value : 1 / value;
  }
}
