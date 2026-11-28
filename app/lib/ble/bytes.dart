int u16le(List<int> data, int offset) {
  return (data[offset] & 0xff) | ((data[offset + 1] & 0xff) << 8);
}

int u32le(List<int> data, int offset) {
  return (data[offset] & 0xff) |
      ((data[offset + 1] & 0xff) << 8) |
      ((data[offset + 2] & 0xff) << 16) |
      ((data[offset + 3] & 0xff) << 24);
}

/// Expands 16-bit, 32-bit, and 128-bit BLE UUIDs to the canonical lowercase form.
String normalizeUuid(String input) {
  final hex = input.replaceAll('-', '').toLowerCase();
  if (hex.length == 4) {
    return '0000$hex-0000-1000-8000-00805f9b34fb';
  }
  if (hex.length == 8) {
    return '$hex-0000-1000-8000-00805f9b34fb';
  }
  if (hex.length != 32) {
    throw FormatException('invalid uuid: $input');
  }
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
