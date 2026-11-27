import 'package:flutter_test/flutter_test.dart';

import 'package:bylwapp/ble/blood_pressure/sfloat.dart';

void main() {
  test('decodes integer and decimal SFLOAT values', () {
    expect(Sfloat.decode(0x0078), 120);
    expect(Sfloat.decode(0x0050), 80);
    expect(
      Sfloat.decode(Sfloat.encode(mantissa: 1205, exponent: -1)),
      closeTo(120.5, 0.0001),
    );
    expect(Sfloat.decode(Sfloat.encode(mantissa: -5, exponent: 0)), -5);
  });

  test('reserves NaN, NRes, infinities, and the reserved mantissa', () {
    expect(Sfloat.decode(Sfloat.nan), isNull);
    expect(Sfloat.decode(Sfloat.nres), isNull);
    expect(Sfloat.decode(Sfloat.reserved), isNull);
    expect(Sfloat.decode(Sfloat.positiveInfinity), double.infinity);
    expect(Sfloat.decode(Sfloat.negativeInfinity), double.negativeInfinity);
  });
}
