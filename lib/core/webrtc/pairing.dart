import 'dart:convert';

import 'base32.dart';
import 'luch_crypto.dart';

/// Pairing secret & room derivation matching `@luch/core` (`pairing.ts`).
class LuchPairing {
  static const int secretBytes = 15;
  static const int secretLength = 24;
  static const int roomIdLength = 10;
  static const int secretGroupSize = 6;
  static const String _roomDomain = 'luch/room/v1|';
  static const String _pairDomain = 'luch/pair/v1|';

  static String createPairingSecret() {
    return CrockfordBase32.encode(LuchCrypto.randomBytes(secretBytes));
  }

  static String normalizeSecret(String input) {
    final norm = CrockfordBase32.normalize(input);
    return norm.length > secretLength ? norm.substring(0, secretLength) : norm;
  }

  static bool isValidSecret(String input) {
    final secret = CrockfordBase32.normalize(input);
    if (secret.length != secretLength) return false;
    if (secret.contains('U')) return false;
    try {
      return CrockfordBase32.decode(secret).length >= 14;
    } catch (_) {
      return false;
    }
  }

  static String roomIdFromSecret(String secret) {
    final normalized = CrockfordBase32.normalize(secret);
    final digest = LuchCrypto.sha256Bytes(utf8.encode('$_roomDomain$normalized'));
    return CrockfordBase32.encode(digest).substring(0, roomIdLength);
  }

  static String pairIdFromSecret(String secret) {
    final normalized = CrockfordBase32.normalize(secret);
    final digest = LuchCrypto.sha256Bytes(utf8.encode('$_pairDomain$normalized'));
    return CrockfordBase32.encode(digest).substring(0, 26);
  }

  static String formatSecret(String secret, {int groupSize = secretGroupSize}) {
    final normalized = CrockfordBase32.normalize(secret);
    final groups = <String>[];
    for (var i = 0; i < normalized.length; i += groupSize) {
      final end = (i + groupSize > normalized.length)
          ? normalized.length
          : i + groupSize;
      groups.add(normalized.substring(i, end));
    }
    return groups.join('-');
  }

  static String buildPairUrl(String serverOrigin, String secret) {
    var clean = serverOrigin.trim();
    if (!clean.endsWith('/')) clean = '$clean/';
    final uri = Uri.parse(clean).replace(
      fragment: 'p=${CrockfordBase32.normalize(secret)}',
    );
    return uri.toString();
  }

  /// Accepts full URL (`#p=...`, `?p=...`, `/p/<secret>`) or raw secret code.
  static String? parsePairInput(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    if (!raw.contains('/') && !raw.contains(':')) {
      return isValidSecret(raw) ? CrockfordBase32.normalize(raw) : null;
    }

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      if (uri.fragment.isNotEmpty) {
        final fragParams = Uri.splitQueryString(uri.fragment);
        final fromHash = fragParams['p'];
        if (fromHash != null && isValidSecret(fromHash)) {
          return CrockfordBase32.normalize(fromHash);
        }
      }
      final fromQuery = uri.queryParameters['p'];
      if (fromQuery != null && isValidSecret(fromQuery)) {
        return CrockfordBase32.normalize(fromQuery);
      }
      final match =
          RegExp(r'(?:^|/)p/([0-9A-Za-z-]+)/?$').firstMatch(uri.path);
      final segment = match?.group(1);
      if (segment != null && isValidSecret(segment)) {
        return CrockfordBase32.normalize(segment);
      }
    }

    return isValidSecret(raw) ? CrockfordBase32.normalize(raw) : null;
  }
}
