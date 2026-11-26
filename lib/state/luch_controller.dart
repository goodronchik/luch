import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/network/ip_resolver.dart';
import '../core/protocol/local_transfer_client.dart';
import '../core/protocol/local_transfer_server.dart';
import '../core/protocol/transfer_models.dart';
import '../core/storage/download_path_service.dart';

/// Central application controller managing LAN server/client state and history.
class LuchController extends ChangeNotifier {
  LuchController() {
    _server.onProgress = _handleProgress;
    _server.onHistory = _handleHistory;
  }

  final LocalTransferServer _server = LocalTransferServer();
  final LocalTransferClient _client = LocalTransferClient();

  List<NetworkInterfaceAddress> _interfaces = const [];
  NetworkInterfaceAddress? _selectedInterface;
  Directory? _saveDirectory;

  final List<SharedFileItem> _queuedSendFiles = [];
  final Map<String, TransferProgress> _transfers = {};
  final List<TransferHistoryEntry> _history = [];

  ParsedSessionUri? _connectedUri;
  SessionInfo? _connectedSession;
  bool _isConnecting = false;
  bool _isTransferringClient = false;
  String? _statusError;

  // Getters
  List<NetworkInterfaceAddress> get interfaces => _interfaces;
  NetworkInterfaceAddress? get selectedInterface => _selectedInterface;
  Directory? get saveDirectory => _saveDirectory;
  String get saveDirectoryPath => _saveDirectory?.path ?? '...';
  String get deviceName => IpResolver.getDeviceDisplayName();

  List<SharedFileItem> get queuedSendFiles =>
      List.unmodifiable(_queuedSendFiles);

  bool get isServerRunning => _server.isRunning;
  SessionMode get serverMode => _server.mode;
  bool get isSending => _server.isRunning && _server.mode == SessionMode.send;
  bool get isHostingReceive =>
      _server.isRunning && _server.mode == SessionMode.receive;

  String? get activeQrUrl {
    final ip = _selectedInterface?.ipAddress;
    if (ip == null || !_server.isRunning) return null;
    return _server.buildSessionUrl(ip);
  }

  ParsedSessionUri? get connectedUri => _connectedUri;
  SessionInfo? get connectedSession => _connectedSession;
  bool get isConnecting => _isConnecting;
  bool get isTransferringClient => _isTransferringClient;
  String? get statusError => _statusError;

  List<TransferProgress> get transfers =>
      _transfers.values.toList().reversed.toList();

  List<TransferHistoryEntry> get history => List.unmodifiable(_history);

  Future<void> initialize() async {
    await Future.wait([
      refreshInterfaces(),
      _initSaveDirectory(),
    ]);
  }

  Future<void> _initSaveDirectory() async {
    try {
      _saveDirectory = await DownloadPathService.resolveLuchDirectory();
      notifyListeners();
    } catch (e) {
      _statusError = 'Не удалось определить папку сохранения: $e';
      notifyListeners();
    }
  }

  Future<void> refreshInterfaces() async {
    final list = await IpResolver.getLocalIpv4Addresses();
    _interfaces = list;
    if (list.isEmpty) {
      _selectedInterface = null;
    } else if (_selectedInterface == null ||
        !list.contains(_selectedInterface)) {
      _selectedInterface = list.first;
    }
    notifyListeners();
  }

  void selectInterface(NetworkInterfaceAddress iface) {
    _selectedInterface = iface;
    notifyListeners();
  }

  void clearError() {
    _statusError = null;
    notifyListeners();
  }

  // --- Send queue & Send Server ---

  Future<void> addLocalPaths(List<String> paths) async {
    final existingPaths = _queuedSendFiles.map((e) => e.localPath).toSet();
    for (final rawPath in paths) {
      if (rawPath.isEmpty || existingPaths.contains(rawPath)) continue;
      final file = File(rawPath);
      if (!await file.exists()) continue;
      final size = await file.length();
      final id =
          'f_${DateTime.now().microsecondsSinceEpoch}_${_queuedSendFiles.length}';
      _queuedSendFiles.add(
        SharedFileItem(
          id: id,
          name: p.basename(rawPath),
          sizeBytes: size,
          localPath: rawPath,
        ),
      );
      existingPaths.add(rawPath);
    }
    notifyListeners();

    // If send server is already active, refresh the session with updated files.
    if (isSending && _queuedSendFiles.isNotEmpty) {
      await startSendSession();
    }
  }

  Future<void> removeQueuedFile(String fileId) async {
    _queuedSendFiles.removeWhere((f) => f.id == fileId);
    notifyListeners();
    if (isSending) {
      if (_queuedSendFiles.isEmpty) {
        await stopServer();
      } else {
        await startSendSession();
      }
    }
  }

  Future<void> clearQueuedFiles() async {
    _queuedSendFiles.clear();
    if (isSending) {
      await stopServer();
    } else {
      notifyListeners();
    }
  }

  Future<void> startSendSession() async {
    _statusError = null;
    if (_queuedSendFiles.isEmpty) {
      _statusError = 'Выберите хотя бы один файл для отправки.';
      notifyListeners();
      return;
    }
    await refreshInterfaces();
    if (_selectedInterface == null) {
      _statusError =
          'Не найден активный локальный IP (подключите Wi-Fi или точку доступа).';
      notifyListeners();
      return;
    }
    await _server.startSendSession(_queuedSendFiles);
    notifyListeners();
  }

  Future<void> startReceiveHostSession() async {
    _statusError = null;
    await refreshInterfaces();
    if (_selectedInterface == null) {
      _statusError =
          'Не найден активный локальный IP (подключите Wi-Fi или точку доступа).';
      notifyListeners();
      return;
    }
    final dir =
        _saveDirectory ?? await DownloadPathService.resolveLuchDirectory();
    _saveDirectory = dir;
    await _server.startReceiveSession(saveDirectory: dir);
    notifyListeners();
  }

  Future<void> stopServer() async {
    await _server.stop();
    notifyListeners();
  }

  // --- Client connect & transfer ---

  Future<bool> connectToQrPayload(String rawPayload) async {
    _statusError = null;
    final parsed = ParsedSessionUri.tryParse(rawPayload);
    if (parsed == null) {
      _statusError =
          'Некорректный QR-код или ссылка. Ожидается адрес вида http://192.168.x.x:порт/s/токен';
      notifyListeners();
      return false;
    }

    _isConnecting = true;
    notifyListeners();
    try {
      final session = await _client.fetchSession(parsed);
      _connectedUri = parsed;
      _connectedSession = session;
      return true;
    } catch (e) {
      _statusError =
          'Не удалось подключиться к ${parsed.host}:${parsed.port}. Убедитесь, что оба устройства в одной сети Wi-Fi.\n($e)';
      return false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  void disconnectPeer() {
    _connectedUri = null;
    _connectedSession = null;
    _statusError = null;
    notifyListeners();
  }

  Future<void> downloadRemoteFiles(List<SharedFileItem> files) async {
    final uri = _connectedUri;
    final session = _connectedSession;
    if (uri == null || session == null || files.isEmpty) return;

    _isTransferringClient = true;
    _statusError = null;
    notifyListeners();

    final dir =
        _saveDirectory ?? await DownloadPathService.resolveLuchDirectory();
    _saveDirectory = dir;

    try {
      for (final file in files) {
        try {
          final saved = await _client.downloadFile(
            sessionUri: uri,
            file: file,
            peerName: session.deviceName,
            targetDirectory: dir,
            onProgress: _handleProgress,
          );
          _handleHistory(
            TransferHistoryEntry(
              id: 'hist_${DateTime.now().microsecondsSinceEpoch}',
              fileName: p.basename(saved.path),
              sizeBytes: await saved.length(),
              direction: TransferDirection.received,
              peerName: session.deviceName,
              timestamp: DateTime.now(),
              success: true,
              localPath: saved.path,
            ),
          );
        } catch (e) {
          _statusError = 'Ошибка скачивания ${file.name}: $e';
          _handleHistory(
            TransferHistoryEntry(
              id: 'hist_${DateTime.now().microsecondsSinceEpoch}',
              fileName: file.name,
              sizeBytes: file.sizeBytes,
              direction: TransferDirection.received,
              peerName: session.deviceName,
              timestamp: DateTime.now(),
              success: false,
              errorMessage: e.toString(),
            ),
          );
        }
      }
    } finally {
      _isTransferringClient = false;
      notifyListeners();
    }
  }

  Future<void> uploadFilesToConnectedPeer(List<String> localPaths) async {
    final uri = _connectedUri;
    final session = _connectedSession;
    if (uri == null || session == null || localPaths.isEmpty) return;

    _isTransferringClient = true;
    _statusError = null;
    notifyListeners();

    try {
      for (final path in localPaths) {
        final f = File(path);
        if (!await f.exists()) continue;
        final size = await f.length();
        final item = SharedFileItem(
          id: 'up_${DateTime.now().microsecondsSinceEpoch}',
          name: p.basename(path),
          sizeBytes: size,
          localPath: path,
        );
        try {
          await _client.uploadFile(
            sessionUri: uri,
            file: item,
            peerName: session.deviceName,
            onProgress: _handleProgress,
          );
          _handleHistory(
            TransferHistoryEntry(
              id: 'hist_${DateTime.now().microsecondsSinceEpoch}',
              fileName: item.name,
              sizeBytes: size,
              direction: TransferDirection.sent,
              peerName: session.deviceName,
              timestamp: DateTime.now(),
              success: true,
              localPath: path,
            ),
          );
        } catch (e) {
          _statusError = 'Ошибка отправки ${item.name}: $e';
          _handleHistory(
            TransferHistoryEntry(
              id: 'hist_${DateTime.now().microsecondsSinceEpoch}',
              fileName: item.name,
              sizeBytes: size,
              direction: TransferDirection.sent,
              peerName: session.deviceName,
              timestamp: DateTime.now(),
              success: false,
              errorMessage: e.toString(),
            ),
          );
        }
      }
    } finally {
      _isTransferringClient = false;
      notifyListeners();
    }
  }

  void clearCompletedTransfers() {
    _transfers.removeWhere(
      (_, v) =>
          v.status == TransferStatus.completed ||
          v.status == TransferStatus.failed,
    );
    notifyListeners();
  }

  void _handleProgress(TransferProgress progress) {
    _transfers[progress.transferId] = progress;
    notifyListeners();
  }

  void _handleHistory(TransferHistoryEntry entry) {
    _history.insert(0, entry);
    notifyListeners();
  }

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }
}
