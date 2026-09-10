import 'dart:math';

final Random _rng = Random.secure();

/// RFC 4122 version 4 identifier.
///
/// Rows are keyed by UUID rather than autoincrement so that two clinics that
/// have never met can create records offline and still merge without
/// collisions when they next reach the hub.
String newId() {
  final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Cryptographically random bytes, for salts and nonces.
List<int> randomBytes(int length) =>
    List<int>.generate(length, (_) => _rng.nextInt(256));
