import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luch/core/protocol/local_transfer_client.dart';
import 'package:luch/core/protocol/local_transfer_server.dart';
import 'package:luch/core/protocol/transfer_models.dart';

void main() {
  group('ParsedSessionUri & sanitizeFileName', () {
    test('parses valid HTTP and luch:// QR links', () {
      final parsed = ParsedSessionUri.tryParse(
        'http://192.168.1.42:54321/s/0123456789abcdef',
      );
      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.42');
      expect(parsed.port, 54321);
      expect(parsed.token, '0123456789abcdef');

      final luchScheme = ParsedSessionUri.tryParse(
        'luch://10.0.0.5:8080/s/abcdef1234567890',
      );
      expect(luchScheme, isNotNull);
      expect(luchScheme!.baseUri.scheme, 'http');
      expect(luchScheme.host, '10.0.0.5');
    });

    test('rejects invalid or missing token links', () {
      expect(ParsedSessionUri.tryParse(''), isNull);
      expect(ParsedSessionUri.tryParse('http://192.168.1.1:8080/s/short'), isNull);
      expect(ParsedSessionUri.tryParse('http://192.168.1.1/s/0123456789abcdef'), isNull);
    });

    test('sanitizes path traversal while preserving Cyrillic filenames', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName(r'..\..\secret\отчёт:2026?.pdf'), 'отчёт_2026_.pdf');
      expect(sanitizeFileName('...'), startsWith('file_'));
    });
  });

  group('LocalTransferServer <-> LocalTransferClient', () {
    late Directory tempRoot;
    late Directory sourceDir;
    late Directory downloadDir;
    late LocalTransferServer server;
    late LocalTransferClient client;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('luch_test_');
      sourceDir = Directory('${tempRoot.path}/src')..createSync();
      downloadDir = Directory('${tempRoot.path}/dst')..createSync();
      server = LocalTransferServer();
      client = LocalTransferClient();
    });

    tearDown(() async {
      await server.stop();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('streams file from sender to receiver and serves Web UI', () async {
      final payloadBytes = Uint8List.fromList(
        List<int>.generate(256 * 1024, (i) => i % 251),
      );
      final srcFile = File('${sourceDir.path}/тест_архив.bin');
      await srcFile.writeAsBytes(payloadBytes);

      await server.startSendSession([
        SharedFileItem(
          id: 'file1',
          name: 'тест_архив.bin',
          sizeBytes: payloadBytes.length,
          localPath: srcFile.path,
        ),
      ]);

      final sessionUrl = server.buildSessionUrl('127.0.0.1');
      expect(sessionUrl, isNotNull);

      final parsed = ParsedSessionUri.tryParse(sessionUrl!)!;
      final session = await client.fetchSession(parsed);
      expect(session.mode, SessionMode.send);
      expect(session.files.length, 1);
      expect(session.files.first.name, 'тест_архив.bin');

      // Download via native client
      final downloaded = await client.downloadFile(
        sessionUri: parsed,
        file: session.files.first,
        peerName: session.deviceName,
        targetDirectory: downloadDir,
      );
      expect(await downloaded.readAsBytes(), payloadBytes);

      // Verify built-in Web Portal returns 200 HTML and rejects invalid token
      final httpClient = HttpClient();
      try {
        final okReq = await httpClient.getUrl(Uri.parse(sessionUrl));
        final okRes = await okReq.close();
        expect(okRes.statusCode, HttpStatus.ok);
        final html = await utf8.decodeStream(okRes);
        expect(html, contains('Луч'));

        final badReq = await httpClient.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/api/v1/session?token=wrong'),
        );
        final badRes = await badReq.close();
        await badRes.drain<void>();
        expect(badRes.statusCode, HttpStatus.unauthorized);
      } finally {
        httpClient.close(force: true);
      }
    });

    test('receives uploaded files in receive mode without overwriting', () async {
      await server.startReceiveSession(saveDirectory: downloadDir);
      final sessionUrl = server.buildSessionUrl('127.0.0.1')!;
      final parsed = ParsedSessionUri.tryParse(sessionUrl)!;

      final session = await client.fetchSession(parsed);
      expect(session.mode, SessionMode.receive);

      final uploadSrc = File('${sourceDir.path}/photo.jpg');
      await uploadSrc.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);

      final item = SharedFileItem(
        id: 'u1',
        name: 'photo.jpg',
        sizeBytes: 8,
        localPath: uploadSrc.path,
      );

      await client.uploadFile(
        sessionUri: parsed,
        file: item,
        peerName: 'TestPeer',
      );
      await client.uploadFile(
        sessionUri: parsed,
        file: item,
        peerName: 'TestPeer',
      );

      final first = File('${downloadDir.path}/photo.jpg');
      final second = File('${downloadDir.path}/photo (1).jpg');
      expect(await first.exists(), isTrue);
      expect(await second.exists(), isTrue);
      expect(await first.readAsBytes(), [1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });
}
