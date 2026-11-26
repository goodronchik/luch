import 'dart:io';

import '../network/ip_resolver.dart';
import '../protocol/local_transfer_client.dart';
import '../protocol/local_transfer_server.dart';
import '../protocol/transfer_models.dart';
import 'file_io_adapter.dart';
import 'local_lan_bridge.dart';

class _IoLocalLanBridge implements LocalLanBridge {
  _IoLocalLanBridge({
    void Function(TransferProgress progress)? onProgress,
    void Function(TransferHistoryEntry entry)? onHistory,
  }) {
    _server.onProgress = onProgress;
    _server.onHistory = onHistory;
  }

  final LocalTransferServer _server = LocalTransferServer();
  final LocalTransferClient _client = LocalTransferClient();

  @override
  bool get isRunning => _server.isRunning;

  @override
  SessionMode get mode => _server.mode;

  @override
  String? buildSessionUrl(String hostIp) => _server.buildSessionUrl(hostIp);

  @override
  Future<List<LanAddress>> listInterfaces() async {
    final list = await IpResolver.getLocalIpv4Addresses();
    return list
        .map(
          (i) => LanAddress(
            interfaceName: i.interfaceName,
            ipAddress: i.ipAddress,
          ),
        )
        .toList();
  }

  @override
  Future<void> startSendSession(List<OutgoingFileSource> files) async {
    final items = files
        .where((f) => f.displayPath != null)
        .map(
          (f) => SharedFileItem(
            id: f.id,
            name: f.name,
            sizeBytes: f.size,
            localPath: f.displayPath,
            mimeType: f.mimeType ?? 'application/octet-stream',
          ),
        )
        .toList();
    await _server.startSendSession(items);
  }

  @override
  Future<void> startReceiveSession({String? customSaveDirectory}) async {
    final dir = (customSaveDirectory != null && customSaveDirectory.isNotEmpty)
        ? Directory(customSaveDirectory)
        : null;
    await _server.startReceiveSession(saveDirectory: dir);
  }

  @override
  Future<void> stop() => _server.stop();

  @override
  Future<SessionInfo> fetchSession(ParsedSessionUri uri) =>
      _client.fetchSession(uri);

  @override
  Future<String> downloadFile({
    required ParsedSessionUri sessionUri,
    required SharedFileItem file,
    required String peerName,
    String? customSaveDirectory,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    final dir = (customSaveDirectory != null && customSaveDirectory.isNotEmpty)
        ? Directory(customSaveDirectory)
        : null;
    final saved = await _client.downloadFile(
      sessionUri: sessionUri,
      file: file,
      peerName: peerName,
      targetDirectory: dir,
      onProgress: onProgress,
    );
    return saved.path;
  }

  @override
  Future<void> uploadFiles({
    required ParsedSessionUri sessionUri,
    required List<OutgoingFileSource> files,
    required String peerName,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    for (final f in files) {
      final path = f.displayPath;
      if (path == null) continue;
      await _client.uploadFile(
        sessionUri: sessionUri,
        file: SharedFileItem(
          id: f.id,
          name: f.name,
          sizeBytes: f.size,
          localPath: path,
        ),
        peerName: peerName,
        onProgress: onProgress,
      );
    }
  }
}

LocalLanBridge createLocalLanBridge({
  void Function(TransferProgress progress)? onProgress,
  void Function(TransferHistoryEntry entry)? onHistory,
}) =>
    _IoLocalLanBridge(onProgress: onProgress, onHistory: onHistory);
