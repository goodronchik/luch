import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../network/ip_resolver.dart';
import '../storage/download_path_service.dart';
import 'transfer_models.dart';
import 'web_portal_html.dart';

typedef ProgressCallback = void Function(TransferProgress progress);
typedef HistoryCallback = void Function(TransferHistoryEntry entry);

/// Embedded local HTTP server for LAN file sharing and receiving via QR URL.
class LocalTransferServer {
  HttpServer? _server;
  String? _token;
  String? _sessionId;
  SessionMode _mode = SessionMode.send;
  List<SharedFileItem> _sharedFiles = const [];
  Directory? _receiveDirectory;

  ProgressCallback? onProgress;
  HistoryCallback? onHistory;

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String? get token => _token;
  SessionMode get mode => _mode;
  List<SharedFileItem> get sharedFiles => List.unmodifiable(_sharedFiles);

  String? buildSessionUrl(String hostIp) {
    final server = _server;
    final tok = _token;
    if (server == null || tok == null) return null;
    return 'http://$hostIp:${server.port}/s/$tok';
  }

  /// Starts serving [files] in [SessionMode.send].
  Future<void> startSendSession(List<SharedFileItem> files) async {
    await stop();
    _mode = SessionMode.send;
    _sharedFiles = List.unmodifiable(files);
    _token = _generateToken();
    _sessionId = _generateToken(byteLength: 8);
    await _bindAndListen();
  }

  /// Starts listening for incoming file uploads in [SessionMode.receive].
  Future<void> startReceiveSession({Directory? saveDirectory}) async {
    await stop();
    _mode = SessionMode.receive;
    _sharedFiles = const [];
    _receiveDirectory =
        saveDirectory ?? await DownloadPathService.resolveLuchDirectory();
    _token = _generateToken();
    _sessionId = _generateToken(byteLength: 8);
    await _bindAndListen();
  }

  Future<void> _bindAndListen() async {
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: false,
    );
    _server = server;
    server.listen(
      _handleRequest,
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    _sessionId = null;
    _sharedFiles = const [];
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      final segments = request.uri.pathSegments;

      // CORS / preflight support for browser requests.
      request.response.headers.set('Cache-Control', 'no-store');

      if (segments.length == 2 && segments[0] == 's') {
        if (!_isAuthorized(segments[1])) {
          await _sendError(request, HttpStatus.unauthorized, 'Неверный токен');
          return;
        }
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.html;
        request.response.write(WebPortalHtml.build(token: _token!));
        await request.response.close();
        return;
      }

      if (path == '/api/v1/session' && request.method == 'GET') {
        if (!_isAuthorized(request.uri.queryParameters['token'])) {
          await _sendError(request, HttpStatus.unauthorized, 'Неверный токен');
          return;
        }
        final info = SessionInfo(
          sessionId: _sessionId ?? '',
          deviceName: IpResolver.getDeviceDisplayName(),
          platform: IpResolver.getPlatformLabel(),
          mode: _mode,
          files: _sharedFiles,
        );
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(info.toJson()));
        await request.response.close();
        return;
      }

      if (segments.length == 4 &&
          segments[0] == 'api' &&
          segments[1] == 'v1' &&
          segments[2] == 'files' &&
          request.method == 'GET') {
        if (!_isAuthorized(request.uri.queryParameters['token'])) {
          await _sendError(request, HttpStatus.unauthorized, 'Неверный токен');
          return;
        }
        if (_mode != SessionMode.send) {
          await _sendError(
            request,
            HttpStatus.forbidden,
            'Сессия не в режиме раздачи',
          );
          return;
        }
        await _handleDownload(request, segments[3]);
        return;
      }

      if (path == '/api/v1/upload' &&
          (request.method == 'POST' || request.method == 'PUT')) {
        if (!_isAuthorized(request.uri.queryParameters['token'])) {
          await _sendError(request, HttpStatus.unauthorized, 'Неверный токен');
          return;
        }
        if (_mode != SessionMode.receive) {
          await _sendError(
            request,
            HttpStatus.forbidden,
            'Сессия не в режиме приёма',
          );
          return;
        }
        await _handleUpload(request);
        return;
      }

      await _sendError(
        request,
        HttpStatus.notFound,
        'Откройте ссылку из QR-кода «Луч».',
      );
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleDownload(HttpRequest request, String fileId) async {
    SharedFileItem? item;
    for (final candidate in _sharedFiles) {
      if (candidate.id == fileId) {
        item = candidate;
        break;
      }
    }
    if (item == null || item.localPath == null) {
      await _sendError(request, HttpStatus.notFound, 'Файл не найден');
      return;
    }

    final file = File(item.localPath!);
    if (!await file.exists()) {
      await _sendError(request, HttpStatus.notFound, 'Файл удалён с диска');
      return;
    }

    final totalLength = await file.length();
    var start = 0;
    var end = totalLength;
    var isRange = false;

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring('bytes='.length).split(',').first;
      final parts = spec.split('-');
      if (parts.length == 2) {
        final parsedStart = int.tryParse(parts[0]);
        final parsedEnd = parts[1].isEmpty ? null : int.tryParse(parts[1]);
        if (parsedStart != null && parsedStart >= 0 && parsedStart < totalLength) {
          start = parsedStart;
          if (parsedEnd != null && parsedEnd >= parsedStart && parsedEnd < totalLength) {
            end = parsedEnd + 1;
          }
          isRange = true;
        }
      }
    }

    final contentLength = end - start;
    final safeName = sanitizeFileName(item.name);
    final encodedName = Uri.encodeComponent(safeName);
    final asciiFallback = safeName.replaceAll(RegExp(r'[^\x20-\x7E]'), '_');

    request.response.statusCode =
        isRange ? HttpStatus.partialContent : HttpStatus.ok;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.set(
      'Content-Disposition',
      'attachment; filename="$asciiFallback"; filename*=UTF-8\'\'$encodedName',
    );
    request.response.headers.contentType = ContentType.binary;
    request.response.contentLength = contentLength;

    if (isRange) {
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${end - 1}/$totalLength',
      );
    }

    final transferId = '${item.id}_${DateTime.now().microsecondsSinceEpoch}';
    final peerIp = request.connectionInfo?.remoteAddress.address ?? 'Устройство';
    final startedAt = DateTime.now();
    var sentBytes = 0;

    onProgress?.call(
      TransferProgress(
        transferId: transferId,
        fileName: item.name,
        bytesTransferred: 0,
        totalBytes: contentLength,
        speedBytesPerSec: 0,
        status: TransferStatus.transferring,
        direction: TransferDirection.sent,
        peerLabel: peerIp,
      ),
    );

    try {
      await for (final chunk in file.openRead(start, end)) {
        request.response.add(chunk);
        sentBytes += chunk.length;
        final elapsedSec =
            max(0.05, DateTime.now().difference(startedAt).inMilliseconds / 1000.0);
        onProgress?.call(
          TransferProgress(
            transferId: transferId,
            fileName: item.name,
            bytesTransferred: sentBytes,
            totalBytes: contentLength,
            speedBytesPerSec: sentBytes / elapsedSec,
            status: TransferStatus.transferring,
            direction: TransferDirection.sent,
            peerLabel: peerIp,
          ),
        );
      }
      await request.response.close();

      final elapsedSec =
          max(0.05, DateTime.now().difference(startedAt).inMilliseconds / 1000.0);
      onProgress?.call(
        TransferProgress(
          transferId: transferId,
          fileName: item.name,
          bytesTransferred: contentLength,
          totalBytes: contentLength,
          speedBytesPerSec: sentBytes / elapsedSec,
          status: TransferStatus.completed,
          direction: TransferDirection.sent,
          peerLabel: peerIp,
        ),
      );
      onHistory?.call(
        TransferHistoryEntry(
          id: transferId,
          fileName: item.name,
          sizeBytes: contentLength,
          direction: TransferDirection.sent,
          peerName: peerIp,
          timestamp: DateTime.now(),
          success: true,
          localPath: item.localPath,
        ),
      );
    } catch (e) {
      onProgress?.call(
        TransferProgress(
          transferId: transferId,
          fileName: item.name,
          bytesTransferred: sentBytes,
          totalBytes: contentLength,
          speedBytesPerSec: 0,
          status: TransferStatus.failed,
          direction: TransferDirection.sent,
          peerLabel: peerIp,
          errorMessage: e.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final rawFilename = request.uri.queryParameters['filename'] ??
        request.headers.value('x-file-name') ??
        'received_${DateTime.now().millisecondsSinceEpoch}.bin';
    final safeName = sanitizeFileName(rawFilename);
    final saveDir =
        _receiveDirectory ?? await DownloadPathService.resolveLuchDirectory();
    final targetFile =
        await DownloadPathService.resolveUniqueTargetFile(saveDir, safeName);
    final partFile = File('${targetFile.path}.part');

    final totalBytes = request.contentLength > 0 ? request.contentLength : 0;
    final transferId = 'up_${DateTime.now().microsecondsSinceEpoch}';
    final peerIp = request.connectionInfo?.remoteAddress.address ?? 'Устройство';
    final startedAt = DateTime.now();
    var receivedBytes = 0;

    onProgress?.call(
      TransferProgress(
        transferId: transferId,
        fileName: p.basename(targetFile.path),
        bytesTransferred: 0,
        totalBytes: totalBytes,
        speedBytesPerSec: 0,
        status: TransferStatus.transferring,
        direction: TransferDirection.received,
        peerLabel: peerIp,
      ),
    );

    IOSink? sink;
    try {
      sink = partFile.openWrite();
      await for (final chunk in request) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final elapsedSec =
            max(0.05, DateTime.now().difference(startedAt).inMilliseconds / 1000.0);
        onProgress?.call(
          TransferProgress(
            transferId: transferId,
            fileName: p.basename(targetFile.path),
            bytesTransferred: receivedBytes,
            totalBytes: totalBytes > 0 ? totalBytes : receivedBytes,
            speedBytesPerSec: receivedBytes / elapsedSec,
            status: TransferStatus.transferring,
            direction: TransferDirection.received,
            peerLabel: peerIp,
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
          bytesTransferred: receivedBytes,
          totalBytes: receivedBytes,
          speedBytesPerSec: receivedBytes / elapsedSec,
          status: TransferStatus.completed,
          direction: TransferDirection.received,
          peerLabel: peerIp,
          savedPath: targetFile.path,
        ),
      );
      onHistory?.call(
        TransferHistoryEntry(
          id: transferId,
          fileName: p.basename(targetFile.path),
          sizeBytes: receivedBytes,
          direction: TransferDirection.received,
          peerName: peerIp,
          timestamp: DateTime.now(),
          success: true,
          localPath: targetFile.path,
        ),
      );

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'ok': true,
          'savedAs': p.basename(targetFile.path),
          'bytes': receivedBytes,
        }),
      );
      await request.response.close();
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
          fileName: safeName,
          bytesTransferred: receivedBytes,
          totalBytes: totalBytes,
          speedBytesPerSec: 0,
          status: TransferStatus.failed,
          direction: TransferDirection.received,
          peerLabel: peerIp,
          errorMessage: e.toString(),
        ),
      );
      await _sendError(request, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _sendError(
    HttpRequest request,
    int statusCode,
    String message,
  ) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'error': message}));
    await request.response.close();
  }

  bool _isAuthorized(String? candidate) {
    final activeToken = _token;
    if (activeToken == null || candidate == null) return false;
    return _constantTimeEquals(activeToken, candidate);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  String _generateToken({int byteLength = 16}) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
