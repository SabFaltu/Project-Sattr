import 'dart:collection';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../core/ids.dart';
import '../crypto_service.dart';

/// Wire format for hub traffic.
///
/// Every request and response body is a single AES-256-GCM envelope keyed by
/// the clinic key. Two properties follow from that, and both are the reason
/// this is not plain JSON over HTTP:
///
///  * a listener on the clinic LAN sees ciphertext, not patient records, and
///  * a peer that cannot produce a valid GCM tag is rejected before its
///    payload is parsed, so the clinic key doubles as admission control.
///
/// Freshness is handled inside the sealed payload by [timestampKey] and
/// [nonceKey], which together bound replay of a captured request.
class SyncProtocol {
  static const int version = 1;
  static const String timestampKey = 'ts';
  static const String nonceKey = 'n';
  static const String payloadKey = 'd';

  /// How far a peer's clock may differ before its requests are refused.
  static const Duration maxSkew = Duration(minutes: 5);

  /// Seals [payload] into a transmittable envelope.
  static Future<String> pack(SecretKey key, Map<String, Object?> payload) async {
    final inner = jsonEncode({
      timestampKey: DateTime.now().millisecondsSinceEpoch,
      nonceKey: newId(),
      payloadKey: payload,
    });
    final sealed = await CryptoService.seal(key, inner);
    return jsonEncode({
      'v': version,
      'nonce': sealed.nonce,
      'ct': sealed.ciphertext,
      'mac': sealed.mac,
    });
  }

  /// Opens an envelope, verifying integrity and freshness.
  ///
  /// [seen] is an optional replay guard owned by the caller; when supplied, a
  /// nonce that has already been accepted is refused.
  static Future<Map<String, Object?>> unpack(
    SecretKey key,
    String body, {
    ReplayGuard? seen,
  }) async {
    final outer = jsonDecode(body);
    if (outer is! Map || outer['v'] != version) {
      throw const SyncProtocolException('Unsupported protocol version');
    }
    final String clear;
    try {
      clear = await CryptoService.open(
        key,
        nonce: outer['nonce'] as String,
        ciphertext: outer['ct'] as String,
        mac: outer['mac'] as String,
      );
    } catch (_) {
      // A failed tag is indistinguishable from a wrong clinic key, and saying
      // which it was would help an attacker more than it helps the clinic.
      throw const SyncProtocolException(
        'Could not authenticate the message. Check that both machines use the '
        'same clinic key.',
      );
    }
    final inner = jsonDecode(clear) as Map<String, Object?>;
    final ts = (inner[timestampKey] as num?)?.toInt();
    if (ts == null) throw const SyncProtocolException('Malformed message');
    final skew = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts))
        .abs();
    if (skew > maxSkew) {
      throw const SyncProtocolException(
        'Message rejected: the clocks on these two machines are more than five '
        'minutes apart.',
      );
    }
    final nonce = inner[nonceKey] as String?;
    if (seen != null && nonce != null && !seen.accept(nonce)) {
      throw const SyncProtocolException('Replayed message rejected');
    }
    return (inner[payloadKey] as Map).cast<String, Object?>();
  }
}

/// Bounded set of recently accepted nonces.
///
/// Sized rather than unbounded so a long-lived hub cannot be pushed into
/// memory exhaustion by an attacker simply making requests; entries older than
/// [SyncProtocol.maxSkew] are unnecessary anyway, since the timestamp check
/// rejects them independently.
class ReplayGuard {
  ReplayGuard({this.capacity = 4096});

  final int capacity;
  final Queue<String> _order = Queue<String>();
  final Set<String> _seen = <String>{};

  /// Records [nonce], returning false if it had already been used.
  bool accept(String nonce) {
    if (!_seen.add(nonce)) return false;
    _order.addLast(nonce);
    while (_order.length > capacity) {
      _seen.remove(_order.removeFirst());
    }
    return true;
  }
}

class SyncProtocolException implements Exception {
  const SyncProtocolException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The hub could not be reached at all.
///
/// Kept distinct from [SyncProtocolException] because the difference decides
/// whether a terminal may fall back to its offline credential cache: an
/// unreachable hub is a network problem, whereas a hub that answered and said
/// no is an answer, and must never be second-guessed locally.
class SyncTransportException extends SyncProtocolException {
  const SyncTransportException(super.message);
}

/// Result of a completed sync run, surfaced to the settings page.
class SyncOutcome {
  const SyncOutcome({
    required this.pushed,
    required this.pulled,
    required this.at,
    this.error,
  });

  const SyncOutcome.failed(String this.error)
      : pushed = 0,
        pulled = 0,
        at = null;

  final int pushed;
  final int pulled;
  final DateTime? at;
  final String? error;

  bool get ok => error == null;

  String get summary {
    if (!ok) return error!;
    if (pushed == 0 && pulled == 0) return 'Already up to date';
    final parts = <String>[
      if (pushed > 0) 'sent $pushed',
      if (pulled > 0) 'received $pulled',
    ];
    return '${parts.join(', ')} ${pushed + pulled == 1 ? 'change' : 'changes'}';
  }
}
