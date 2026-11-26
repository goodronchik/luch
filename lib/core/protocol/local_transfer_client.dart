import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../storage/download_path_service.dart';
import 'transfer_models.dart';

/// Streaming HTTP client used to connect to a peer's QR session.
class LocalTransferClient {
  Future<SessionInfo> fetchSession(ParsedSessionUri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri.apiUri('/api/v1/session'));
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = await utf8.decodeStream(response);

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Сервер отклонил подключение (${response.statusCode})',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Некорректный ответ сессии');
      }
      return SessionInfo.fromJson(decoded);
    } finally {
      client.close(force: true);
    }
  }

  /// Streams a remote file directly to disk without buffering it in memory.
  Future<File> downloadFile({
    required ParsedSessionUri sessionUri,
    required SharedFileItem file,
    required String peerName,
    Directory? targetDirectory,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    final dir =
        targetDirectory ?? await DownloadPathService.resolveLuchDirectory();
    final targetFile =
        await DownloadPathService.resolveUniqueTargetFile(dir, file.name);
    final partFile = File('${targetFile.path}.part');
    final transferId = 'dl_${file.id}_${DateTime.now().microsecondsSinceEpoch}';

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    IOSink? sink;
    var received = 0;

    try {
      final url = sessionUri.apiUri('/api/v1/files/${Uri.encodeComponent(file.id)}');
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Ошибка загрузки (${response.statusCode})');
      }

      final total =
          response.contentLength > 0 ? response.contentLength : file.sizeBytes;
      final startedAt = DateTime.now();
      sink = partFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        final elapsedSec =
            max(0.05, DateTime.now().difference(startedAt).inMilliseconds / 1000.0);
        onProgress?.call(
          TransferProgress(
            transferId: transferId,
            fileName: p.basename(targetFile.path),
            bytesTransferred: received,
            totalBytes: total > 0 ? total : received,
            speedBytesPerSec: received / elapsedSec,
            status: TransferStatus.transferring,
            direction: TransferDirection.received,
            peerLabel: peerName,
          ),
        );
      }

      await sink.flush();
      await sink.close();
      sink = null;

      await partFile.rename(targetFile.path);
      final elapsedSec =
          max(0.05, DateTime.now().difference(startedAt).inMilliseconds / 1000.0);
      onProgress?.call(
        TransferProgress(
          transferId: transferId,
          fileName: p.basename(targetFile.path),
          bytesTransferred: received,
          totalBytes: received,
          speedBytesPerSec: received / elapsedSec,
          status: TransferStatus.completed,
          direction: TransferDirection.received,
          peerLabel: peerName,
          savedPath: targetFile.path,
        ),
      );
      return targetFile;
    } catch (e) {
      await sink?.close();
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      onProgress?.call(
        TransferProgress(
          transferId: transferId,
          fileName: file.name,
          bytesTransferred: received,
          totalBytes: file.sizeBytes,
          speedBytesPerSec: 0,
          status: TransferStatus.failed,
          direction: TransferDirection.received,
          peerLabel: peerName,
          errorMessage: e.toString(),
        ),
      );
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Streams a local file to a peer running in [SessionMode.receive].
  Future<void> uploadFile({
    required ParsedSessionUri sessionUri,
    required SharedFileItem file,
    required String peerName,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    final localPath = file.localPath;
    if (localPath == null) {
      throw ArgumentError('Отсутствует локальный путь файла');
    }
    final localFile = File(localPath);
    final total = await localFile.length();
    final transferId = 'ul_${file.id}_${DateTime.now().microsecondsSinceEpoch}';

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    var sent = 0;

    try {
      final url = sessionUri.apiUri('/api/v1/upload', {'filename': file.name});
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType.binary;
      request.contentLength = total;

      final startedAt = DateTime.now();
      await for (final chunk in localFile.openRead()) {
        request.add(chunk);
        sent += chunk.length;
        final elapsedSec =
            max(0.05, DateTime.now().difference(startedAt).inMilliseconds / 1000.0);
        onProgress?.call(
          TransferProgress(
            transferId: transferId,
            fileName: file.name,
            bytesTransferred: sent,
            totalBytes: total,
            speedBytesPerSec: sent / elapsedSec,
            status: TransferStatus.transferring,
            direction: TransferDirection.sent,
            peerLabel: peerName,
          ),
        );
      }

      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Ошибка отправки (${response.statusCode})');
      }

      final elapsedSec =
          max(0.05, DateTime.now().difference(startedAt).inMilliseconds / 1000.0);
      onProgress?.call(
        TransferProgress(
          transferId: transferId,
          fileName: file.name,
          bytesTransferred: total,
          totalBytes: total,
          speedBytesPerSec: total / elapsedSec,
          status: TransferStatus.completed,
          direction: TransferDirection.sent,
          peerLabel: peerName,
          savedPath: localPath,
        ),
      );
    } catch (e) {
      onProgress?.call(
        TransferProgress(
          transferId: transferId,
          fileName: file.name,
          bytesTransferred: sent,
          totalBytes: total,
          speedBytesPerSec: 0,
          status: TransferStatus.failed,
          direction: TransferDirection.sent,
          peerLabel: peerName,
          errorMessage: e.toString(),
        ),
      );
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
