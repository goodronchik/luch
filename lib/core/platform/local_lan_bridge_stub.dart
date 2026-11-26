import '../protocol/transfer_models.dart';
import 'file_io_adapter.dart';
import 'local_lan_bridge.dart';

class _StubLocalLanBridge implements LocalLanBridge {
  @override
  bool get isRunning => false;

  @override
  SessionMode get mode => SessionMode.send;

  @override
  String? buildSessionUrl(String hostIp) => null;

  @override
  Future<List<LanAddress>> listInterfaces() async => const [];

  @override
  Future<void> startSendSession(List<OutgoingFileSource> files) async {
    throw UnsupportedError('Локальный HTTP-сервер недоступен в браузере');
  }

  @override
  Future<void> startReceiveSession({String? customSaveDirectory}) async {
    throw UnsupportedError('Локальный HTTP-сервер недоступен в браузере');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<SessionInfo> fetchSession(ParsedSessionUri uri) async {
    throw UnsupportedError('Локальный HTTP-клиент недоступен в браузере');
  }

  @override
  Future<String> downloadFile({
    required ParsedSessionUri sessionUri,
    required SharedFileItem file,
    required String peerName,
    String? customSaveDirectory,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    throw UnsupportedError('Локальный HTTP-клиент недоступен в браузере');
  }

  @override
  Future<void> uploadFiles({
    required ParsedSessionUri sessionUri,
    required List<OutgoingFileSource> files,
    required String peerName,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    throw UnsupportedError('Локальный HTTP-клиент недоступен в браузере');
  }
}

LocalLanBridge createLocalLanBridge({
  void Function(TransferProgress progress)? onProgress,
  void Function(TransferHistoryEntry entry)? onHistory,
}) =>
    _StubLocalLanBridge();
