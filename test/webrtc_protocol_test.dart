import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luch/core/webrtc/base32.dart';
import 'package:luch/core/webrtc/luch_crypto.dart';
import 'package:luch/core/webrtc/pairing.dart';
import 'package:luch/core/webrtc/transfer_protocol.dart';

void main() {
  group('CrockfordBase32 & LuchPairing', () {
    test('round-trips bytes through Crockford Base32', () {
      final raw = Uint8List.fromList(List<int>.generate(15, (i) => i * 17 + 3));
      final encoded = CrockfordBase32.encode(raw);
      expect(encoded.length, 24);
      expect(CrockfordBase32.decode(encoded), raw);
    });

    test('creates valid 24-char secret and derives roomId / pairId', () {
      final secret = LuchPairing.createPairingSecret();
      expect(LuchPairing.isValidSecret(secret), isTrue);

      final formatted = LuchPairing.formatSecret(secret);
      expect(formatted.split('-').length, 4);
      expect(LuchPairing.parsePairInput(formatted), secret);

      final url = LuchPairing.buildPairUrl('https://main.lolkas.ru/luch', secret);
      expect(url, 'https://main.lolkas.ru/luch/#p=$secret');
      expect(LuchPairing.parsePairInput(url), secret);

      final roomId = LuchPairing.roomIdFromSecret(secret);
      final pairId = LuchPairing.pairIdFromSecret(secret);
      expect(roomId.length, 10);
      expect(pairId.length, 26);
    });
  });

  group('LuchCrypto DTLS-HMAC auth', () {
    test('derives HKDF key and verifies channel auth tag', () {
      final secret = LuchPairing.createPairingSecret();
      const sdp =
          'v=0\r\na=fingerprint:sha-256 AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99\r\n';
      final fp1 = LuchCrypto.normalizeDtlsFingerprint(sdp);
      final fp2 = '11' * 32;
      expect(fp1.length, 64);

      final tag = LuchCrypto.channelAuthTag(secret, fp1, fp2);
      expect(LuchCrypto.verifyChannelAuthTag(secret, fp1, fp2, tag), isTrue);
      expect(LuchCrypto.verifyChannelAuthTag(secret, fp2, fp1, tag), isFalse);
    });
  });

  group('TransferProtocol framing & manifest', () {
    test('encodes and decodes binary data frames', () {
      final payload = Uint8List.fromList(utf8.encode('hello luch'));
      final frame = encodeDataFrame(7, 42, payload);
      final decoded = decodeDataFrame(frame);
      expect(decoded.fileId, 7);
      expect(decoded.seq, 42);
      expect(decoded.payload, payload);
    });

    test('creates and validates manifest with sanitized filenames', () {
      final manifest = TransferManifest.create(
        senderName: 'TestMac',
        files: const [
          OutgoingFileDescriptor(name: '../../отчёт.pdf', size: 1234),
        ],
      );
      final roundTrip = TransferManifest.validate(manifest.toJson());
      expect(roundTrip.entries.length, 1);
      expect(roundTrip.entries.first.name, 'отчёт.pdf');
      expect(roundTrip.totalBytes, 1234);
    });
  });
}
