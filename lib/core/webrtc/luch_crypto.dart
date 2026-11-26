import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'base32.dart';

/// Cryptographic primitives wire-compatible with `@luch/core` (WebCrypto HKDF + HMAC-SHA256).
class LuchCrypto {
  static final Uint8List _hkdfSalt = Uint8List.fromList(utf8.encode('luch/v1'));
  static final Uint8List _hkdfInfo =
      Uint8List.fromList(utf8.encode('pairing-channel-auth'));
  static const String _tagDomain = 'luch/v1/auth';

  static Uint8List randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }

  static Uint8List sha256Bytes(List<int> data) {
    return Uint8List.fromList(sha256.convert(data).bytes);
  }

  static String sha256Hex(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }

  static Uint8List hmacSha256(List<int> key, List<int> data) {
    final hmac = Hmac(sha256, key);
    return Uint8List.fromList(hmac.convert(data).bytes);
  }

  /// RFC 5869 HKDF-SHA256.
  static Uint8List hkdfSha256(
    Uint8List ikm, {
    Uint8List? salt,
    Uint8List? info,
    int length = 32,
  }) {
    final effectiveSalt =
        (salt == null || salt.isEmpty) ? Uint8List(32) : salt;
    final prk = hmacSha256(effectiveSalt, ikm);
    final effectiveInfo = info ?? Uint8List(0);

    const hashLen = 32;
    final n = (length + hashLen - 1) ~/ hashLen;
    final okm = BytesBuilder(copy: false);
    var previous = Uint8List(0);

    for (var i = 1; i <= n; i++) {
      final input = BytesBuilder(copy: false)
        ..add(previous)
        ..add(effectiveInfo)
        ..addByte(i);
      previous = hmacSha256(prk, input.toBytes());
      okm.add(previous);
    }

    return Uint8List.sublistView(okm.toBytes(), 0, length);
  }

  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String normalizeDtlsFingerprint(String sdp) {
    final match =
        RegExp(r'a=fingerprint:sha-256\s+([0-9a-fA-F:]+)').firstMatch(sdp);
    final raw = match?.group(1);
    if (raw == null) {
      throw const FormatException('В SDP не найден отпечаток DTLS (sha-256)');
    }
    final hex = raw.replaceAll(':', '').toLowerCase();
    if (hex.length != 64) {
      throw const FormatException('Неожиданная длина отпечатка DTLS');
    }
    return hex;
  }

  static Uint8List pairingAuthKey(String secret) {
    final normalized = CrockfordBase32.normalize(secret);
    final raw = CrockfordBase32.decode(normalized);
    if (raw.length < 14) {
      throw const FormatException('Слишком короткий секрет сопряжения');
    }
    return hkdfSha256(raw, salt: _hkdfSalt, info: _hkdfInfo, length: 32);
  }

  static String channelAuthTag(
    String secret,
    String hostFingerprint,
    String joinFingerprint,
  ) {
    final key = pairingAuthKey(secret);
    final transcript = utf8.encode(
      '$_tagDomain\nhost=${hostFingerprint.toLowerCase()}\njoin=${joinFingerprint.toLowerCase()}',
    );
    final tag = hmacSha256(key, transcript);
    return tag.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool verifyChannelAuthTag(
    String secret,
    String hostFingerprint,
    String joinFingerprint,
    String receivedTag,
  ) {
    final expected = channelAuthTag(secret, hostFingerprint, joinFingerprint);
    final a = utf8.encode(expected);
    final b = utf8.encode(receivedTag.trim().toLowerCase());
    return constantTimeEquals(a, b);
  }
}
