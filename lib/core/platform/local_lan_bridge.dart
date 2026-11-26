import '../protocol/transfer_models.dart';
import 'file_io_adapter.dart';
import 'local_lan_bridge_stub.dart'
    if (dart.library.io) 'local_lan_bridge_io.dart' as impl;

class LanAddress {
  const LanAddress({required this.interfaceName, required this.ipAddress});

  final String interfaceName;
  final String ipAddress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanAddress &&
          interfaceName == other.interfaceName &&
          ipAddress == other.ipAddress;

  @override
  int get hashCode => Object.hash(interfaceName, ipAddress);
}

abstract class LocalLanBridge {
  factory LocalLanBridge({
    void Function(TransferProgress progress)? onProgress,
    void Function(TransferHistoryEntry entry)? onHistory,
  }) =>
      impl.createLocalLanBridge(onProgress: onProgress, onHistory: onHistory);

  bool get isRunning;
  SessionMode get mode;

  Future<List<LanAddress>> listInterfaces();
  String? buildSessionUrl(String hostIp);
  Future<void> startSendSession(List<OutgoingFileSource> files);
  Future<void> startReceiveSession({String? customSaveDirectory});
  Future<void> stop();

  Future<SessionInfo> fetchSession(ParsedSessionUri uri);
  Future<String> downloadFile({
    required ParsedSessionUri sessionUri,
    required SharedFileItem file,
    required String peerName,
    String? customSaveDirectory,
    void Function(TransferProgress progress)? onProgress,
  });
  Future<void> uploadFiles({
    required ParsedSessionUri sessionUri,
    required List<OutgoingFileSource> files,
    required String peerName,
    void Function(TransferProgress progress)? onProgress,
  });
}
