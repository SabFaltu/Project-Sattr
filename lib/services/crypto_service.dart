import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../core/ids.dart';

/// Password hashing and channel encryption.
///
/// Two independent secrets exist in this application and it matters that they
/// stay independent:
///
///  * a **user password**, stretched with PBKDF2 before it is ever stored, and
///  * a **clinic key**, a shared secret configured once per site that protects
///    traffic between an install and its hub.
///
/// Neither is ever written to disk in the clear, and a password hash never
/// crosses the network in either direction.
class CryptoService {
  static const String algo = 'pbkdf2-hmac-sha256';

  /// Work factor for stored password verifiers.
  static const int passwordIterations = 150000;

  /// Work factor for deriving the channel key from the clinic key. Lower than
  /// [passwordIterations] because it runs on every sync, and the input is a
  /// high-entropy generated key rather than a human-chosen password.
  static const int channelIterations = 50000;

  static const int _keyBits = 256;

  static final _gcm = AesGcm.with256bits();

  /// Derives a verifier for [password] against [salt].
  static Future<String> hashPassword(
    String password,
    String salt, {
    int iterations = passwordIterations,
  }) async {
    final bytes = await _derive(
      utf8.encode(password),
      base64Decode(salt),
      iterations,
    );
    return base64Encode(bytes);
  }

  /// Constant-time comparison of a freshly derived verifier against a stored
  /// one, so a wrong password cannot be narrowed down by timing.
  static Future<bool> verifyPassword(
    String password,
    String salt,
    String expectedHash, {
    int iterations = passwordIterations,
  }) async {
    final actual = await hashPassword(password, salt, iterations: iterations);
    return constantTimeEquals(
      base64Decode(actual),
      base64Decode(expectedHash),
    );
  }

  static String newSalt([int length = 16]) =>
      base64Encode(randomBytes(length));

  /// A fresh clinic key, shown to the administrator once so it can be typed
  /// into the other terminals.
  ///
  /// Formatted in dash-separated groups because someone has to read it off one
  /// screen and type it into another.
  static String newClinicKey() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final bytes = randomBytes(20);
    final chars = bytes.map((b) => alphabet[b % alphabet.length]).join();
    return [
      for (var i = 0; i < chars.length; i += 5) chars.substring(i, i + 5),
    ].join('-');
  }

  static Future<List<int>> _derive(
    List<int> secret,
    List<int> salt,
    int iterations,
  ) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: _keyBits,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
    );
    return key.extractBytes();
  }

  /// Derives the AES key used to protect sync traffic from the clinic key.
  ///
  /// The salt is a fixed protocol string rather than a random value: both ends
  /// must arrive at the same key knowing only the shared clinic key.
  static Future<SecretKey> channelKey(String clinicKey) async {
    final bytes = await _derive(
      utf8.encode(clinicKey.trim().toUpperCase()),
      utf8.encode('sattra-sync-v1'),
      channelIterations,
    );
    return SecretKey(bytes);
  }

  /// Seals [plaintext] with AES-256-GCM.
  ///
  /// Returns nonce, ciphertext and tag separately so the envelope stays
  /// self-describing and a future algorithm change stays possible.
  static Future<({String nonce, String ciphertext, String mac})> seal(
    SecretKey key,
    String plaintext,
  ) async {
    final nonce = _gcm.newNonce();
    final box = await _gcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return (
      nonce: base64Encode(box.nonce),
      ciphertext: base64Encode(box.cipherText),
      mac: base64Encode(box.mac.bytes),
    );
  }

  /// Opens a sealed envelope. Throws if the tag does not verify, which is what
  /// rejects both tampering and a peer using the wrong clinic key.
  static Future<String> open(
    SecretKey key, {
    required String nonce,
    required String ciphertext,
    required String mac,
  }) async {
    final box = SecretBox(
      base64Decode(ciphertext),
      nonce: base64Decode(nonce),
      mac: Mac(base64Decode(mac)),
    );
    final clear = await _gcm.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }

  /// Short, stable fingerprint of a clinic key, safe to display.
  ///
  /// Lets an administrator confirm two terminals hold the same key without
  /// either screen showing the key itself.
  static Future<String> fingerprint(String clinicKey) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(clinicKey.trim().toUpperCase()),
      secretKey: SecretKey(utf8.encode('sattra-fingerprint-v1')),
    );
    final hex = mac.bytes
        .take(4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return '${hex.substring(0, 4)}-${hex.substring(4)}';
  }

  /// Comparison whose running time does not depend on where the first
  /// difference is.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// An opaque bearer token for an authenticated session.
  static String newToken() => base64Url.encode(
        Uint8List.fromList(randomBytes(32)),
      ).replaceAll('=', '');
}
