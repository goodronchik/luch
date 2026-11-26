import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/platform/file_io_adapter.dart';
import '../core/platform/local_lan_bridge.dart';
import '../core/platform/platform_info.dart';
import '../core/protocol/transfer_models.dart';
import '../core/storage/paired_devices_store.dart';
import '../core/webrtc/pairing.dart';
import '../core/webrtc/peer_session.dart';
import '../core/webrtc/presence_client.dart';
import '../core/webrtc/signaling_client.dart';
import '../core/webrtc/transfer_protocol.dart';
import '../core/webrtc/transfer_session.dart';

enum WebRtcPhase {
  idle,
  waiting,
  connecting,
  connected,
  transferring,
  done,
  error,
}

enum SendContentMode { files, text }

class LuchController extends ChangeNotifier {
  LuchController() {
    _lanBridge = LocalLanBridge(
      onProgress: _handleProgress,
      onHistory: _handleHistory,
    );
  }

  final LuchPreferencesStore _prefsStore = LuchPreferencesStore();
  late final LocalLanBridge _lanBridge;

  LuchSettings _settings = LuchSettings(
    deviceId: '',
    deviceName: PlatformInfo.defaultDeviceName(),
    serverOrigin: LuchSettings.defaultServerOrigin,
    autoAccept: true,
    theme: AppThemePreference.dark,
  );
  List<PairedDevice> _devices = [];
  String _defaultSaveDir = '';

  // Server config (STUN/TURN + signalingPath)
  List<Map<String, dynamic>> _iceServers = const [
    {
      'urls': ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478']
    }
  ];
  String _signalingPath = '/luch/signal';
  DateTime? _configFetchedAt;

  // WebRTC / Signaling / Presence state
  SignalingClient? _signaling;
  PeerSession? _peer;
  TransferSession? _transfer;
  PresenceClient? _presence;

  WebRtcPhase _phase = WebRtcPhase.idle;
  SendContentMode _sendMode = SendContentMode.files;
  bool _isHostRole = false;
  String? _activeSecret;
  String? _activePairUrl;
  int? _expiresAtMs;
  String? _peerName;
  String _signalingStatus = 'offline';
  String _presenceStatus = 'offline';
  IncomingCallEvent? _incomingCall;
  String? _outgoingCallId;
  Timer? _outgoingCallTimer;
  Timer? _joinRetryTimer;
  int _joinRetryAttempts = 0;

  TransferManifest? _pendingOffer;
  String? _incomingText;
  String? _statusError;
  String? _notice;

  // Queued files & transfers & history
  final List<OutgoingFileSource> _queuedFiles = [];
  String _draftText = '';
  final Map<String, TransferProgress> _transfers = {};
  final List<TransferHistoryEntry> _history = [];

  // Optional Local LAN HTTP state (native platforms only)
  List<LanAddress> _lanInterfaces = const [];
  LanAddress? _selectedLanInterface;
  ParsedSessionUri? _connectedLanUri;
  SessionInfo? _connectedLanSession;
  bool _isLanTransferring = false;

  // Getters
  LuchSettings get settings => _settings;
  List<PairedDevice> get devices => List.unmodifiable(_devices);
  String get saveDirectoryDisplay =>
      (_settings.customSaveDirectory?.isNotEmpty ?? false)
          ? _settings.customSaveDirectory!
          : _defaultSaveDir;

  WebRtcPhase get phase => _phase;
  SendContentMode get sendMode => _sendMode;
  bool get isHostRole => _isHostRole;
  String? get activeSecret => _activeSecret;
  String? get activeManualCode =>
      _activeSecret != null ? LuchPairing.formatSecret(_activeSecret!) : null;
  String? get activePairUrl => _activePairUrl;
  int? get expiresAtMs => _expiresAtMs;
  String? get peerName => _peerName;
  String get signalingStatus => _signalingStatus;
  String get presenceStatus => _presenceStatus;
  IncomingCallEvent? get incomingCall => _incomingCall;
  TransferManifest? get pendingOffer => _pendingOffer;
  String? get incomingText => _incomingText;
  String? get statusError => _statusError;
  String? get notice => _notice;
  int get iceServersCount => _iceServers.length;

  List<OutgoingFileSource> get queuedFiles => List.unmodifiable(_queuedFiles);
  String get draftText => _draftText;
  List<TransferProgress> get transfers =>
      _transfers.values.toList().reversed.toList();
  List<TransferHistoryEntry> get history => List.unmodifiable(_history);

  // Local LAN getters
  bool get supportsLocalLan => PlatformInfo.supportsLocalLanServer;
  bool get isLanServerRunning => _lanBridge.isRunning;
  bool get isLanSending =>
      _lanBridge.isRunning && _lanBridge.mode == SessionMode.send;
  bool get isLanHostingReceive =>
      _lanBridge.isRunning && _lanBridge.mode == SessionMode.receive;
  List<LanAddress> get lanInterfaces => _lanInterfaces;
  LanAddress? get selectedLanInterface => _selectedLanInterface;
  String? get activeLanQrUrl {
    final ip = _selectedLanInterface?.ipAddress;
    if (ip == null || !_lanBridge.isRunning) return null;
    return _lanBridge.buildSessionUrl(ip);
  }

  SessionInfo? get connectedLanSession => _connectedLanSession;
  bool get isLanTransferring => _isLanTransferring;

  Future<void> initialize() async {
    final loaded = await _prefsStore.load(
      defaultDeviceName: PlatformInfo.defaultDeviceName(),
    );
    _settings = loaded.settings;
    _devices = loaded.devices;
    _defaultSaveDir = await PlatformFileStorage.resolveDefaultSaveDirectoryPath();

    _presence = PresenceClient(
      url: _buildWsUrl(),
      deviceId: _settings.deviceId,
      deviceName: _settings.deviceName,
      callbacks: PresenceCallbacks(
        onStateChange: (status) {
          _presenceStatus = status;
          notifyListeners();
        },
        onIncomingCall: _handleIncomingCall,
        onCallResult: _handleCallResult,
        onCallReply: _handleCallReply,
      ),
    );
    _syncPresenceRegistration();

    if (PlatformInfo.supportsLocalLanServer) {
      await refreshLanInterfaces();
    }

    notifyListeners();
    unawaited(loadServerConfig(force: true));

    // If opened via Web URL `#p=<secret>`, auto-join!
    final initialSecret = PlatformInfo.consumeInitialPairSecret();
    if (initialSecret != null) {
      await startWebRtcJoin(initialSecret);
    }
  }

  // --- Settings & Paired Devices ---

  Future<void> updateSettings({
    String? deviceName,
    String? serverOrigin,
    bool? autoAccept,
    AppThemePreference? theme,
    String? customSaveDirectory,
    bool clearCustomSaveDirectory = false,
  }) async {
    final nextName = (deviceName != null && deviceName.trim().isNotEmpty)
        ? deviceName.trim().sliceSafe(40)
        : _settings.deviceName;
    final nextOrigin = (serverOrigin != null && serverOrigin.trim().isNotEmpty)
        ? _normalizeServerOrigin(serverOrigin)
        : _settings.serverOrigin;

    final originChanged = nextOrigin != _settings.serverOrigin;

    _settings = _settings.copyWith(
      deviceName: nextName,
      serverOrigin: nextOrigin,
      autoAccept: autoAccept,
      theme: theme,
      customSaveDirectory: customSaveDirectory,
      clearCustomSaveDirectory: clearCustomSaveDirectory,
    );
    await _prefsStore.saveSettings(_settings);

    if (originChanged) {
      _configFetchedAt = null;
      await loadServerConfig(force: true);
    }
    _syncPresenceRegistration();
    notifyListeners();
  }

  String _normalizeServerOrigin(String raw) {
    var clean = raw.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  Future<void> forgetDevice(String id) async {
    _devices.removeWhere((d) => d.id == id);
    await _prefsStore.saveDevices(_devices);
    _syncPresenceRegistration();
    notifyListeners();
  }

  Future<void> clearAllDevices() async {
    _devices.clear();
    await _prefsStore.saveDevices(_devices);
    _syncPresenceRegistration();
    notifyListeners();
  }

  void _upsertPairedDevice({
    required String peerDeviceId,
    required String name,
    required String secret,
  }) {
    final normalized = LuchPairing.normalizeSecret(secret);
    final pairId = LuchPairing.pairIdFromSecret(normalized);
    final id = peerDeviceId.isNotEmpty ? peerDeviceId : 'pair:$pairId';
    _devices.removeWhere((d) => d.id == id || d.pairId == pairId);
    _devices.insert(
      0,
      PairedDevice(
        id: id,
        name: name.isNotEmpty ? name : 'Устройство',
        secret: normalized,
        pairId: pairId,
        lastSeenMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _prefsStore.saveDevices(_devices);
    _syncPresenceRegistration();
  }

  void _syncPresenceRegistration() {
    final pairs = _devices.map((d) => d.pairId).where((p) => p.isNotEmpty).toList();
    _presence?.updateRegistration(
      pairs: pairs,
      deviceName: _settings.deviceName,
      newUrl: _buildWsUrl(),
    );
  }

  // --- Server config (/api/config) ---

  Future<void> loadServerConfig({bool force = false}) async {
    final last = _configFetchedAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 10)) {
      return;
    }

    try {
      final configUri = Uri.parse('${_settings.serverOrigin}/api/config');
      final response = await http
          .get(configUri, headers: {'Cache-Control': 'no-store'})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final rawIce = decoded['iceServers'];
          if (rawIce is List && rawIce.isNotEmpty) {
            _iceServers = rawIce
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
          }
          final sigPath = decoded['signalingPath'];
          if (sigPath is String && sigPath.startsWith('/')) {
            _signalingPath = sigPath;
          }
          _configFetchedAt = DateTime.now();
          _syncPresenceRegistration();
          notifyListeners();
        }
      }
    } catch (_) {
      // Fallback to STUN servers if config endpoint is temporarily unreachable.
    }
  }

  String _buildWsUrl() {
    final originUri = Uri.parse(_settings.serverOrigin);
    final wsScheme = originUri.scheme == 'https' ? 'wss' : 'ws';
    final path = _signalingPath.isNotEmpty
        ? _signalingPath
        : '${originUri.path}/signal';
    return originUri.replace(scheme: wsScheme, path: path, query: null, fragment: null).toString();
  }

  // --- Draft files & text ---

  void setSendMode(SendContentMode mode) {
    _sendMode = mode;
    notifyListeners();
  }

  void setDraftText(String text) {
    _draftText = text;
    notifyListeners();
  }

  Future<void> addOutgoingSources(List<OutgoingFileSource> sources) async {
    final existingNames =
        _queuedFiles.map((e) => '${e.name}:${e.size}:${e.displayPath}').toSet();
    for (final src in sources) {
      final key = '${src.name}:${src.size}:${src.displayPath}';
      if (!existingNames.contains(key)) {
        _queuedFiles.add(src);
        existingNames.add(key);
      }
    }
    notifyListeners();
  }

  void removeQueuedFile(String id) {
    _queuedFiles.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  void clearQueuedFiles() {
    _queuedFiles.clear();
    notifyListeners();
  }

  void clearStatusMessages() {
    _statusError = null;
    _notice = null;
    notifyListeners();
  }

  void clearIncomingText() {
    _incomingText = null;
    notifyListeners();
  }

  void clearCompletedTransfers() {
    _transfers.removeWhere(
      (_, v) =>
          v.status == TransferStatus.completed ||
          v.status == TransferStatus.failed,
    );
    notifyListeners();
  }

  // --- WebRTC Host & Join flows ---

  Future<void> startWebRtcSendFiles() async {
    if (_queuedFiles.isEmpty) {
      _statusError = 'Выберите хотя бы один файл для отправки.';
      notifyListeners();
      return;
    }
    _sendMode = SendContentMode.files;
    await _startHostRoom();
  }

  Future<void> startWebRtcSendText() async {
    if (_draftText.trim().isEmpty) {
      _statusError = 'Введите текст для отправки.';
      notifyListeners();
      return;
    }
    _sendMode = SendContentMode.text;
    await _startHostRoom();
  }

  Future<void> startWebRtcPairOnly() async {
    _queuedFiles.clear();
    _draftText = '';
    _sendMode = SendContentMode.files;
    await _startHostRoom();
  }

  Future<void> _startHostRoom() async {
    await resetWebRtcSession();
    _statusError = null;
    _notice = null;

    await loadServerConfig();
    final secret = LuchPairing.createPairingSecret();
    final roomId = LuchPairing.roomIdFromSecret(secret);

    _isHostRole = true;
    _activeSecret = secret;
    _activePairUrl = LuchPairing.buildPairUrl(_settings.serverOrigin, secret);
    _phase = WebRtcPhase.waiting;
    _signalingStatus = 'connecting';
    notifyListeners();

    final signaling = SignalingClient(
      url: _buildWsUrl(),
      callbacks: SignalingCallbacks(
        onOpen: () {
          _signalingStatus = 'online';
          notifyListeners();
        },
        onHosted: (expiresAt) {
          _expiresAtMs = expiresAt;
          notifyListeners();
        },
        onMatched: (peerId, peerDevice, initiator) =>
            _handleMatched(peerDevice, initiator),
        onSignal: (data) => _peer?.handleSignal(data),
        onPeerLeft: _handlePeerLeft,
        onError: _handleSignalingError,
        onClose: (reason) {
          _signalingStatus = 'offline';
          if (_phase == WebRtcPhase.waiting || _phase == WebRtcPhase.connecting) {
            _phase = WebRtcPhase.error;
            _statusError = reason;
          }
          notifyListeners();
        },
      ),
    );
    _signaling = signaling;

    try {
      await signaling.connect();
      signaling.host(roomId, secret, _settings.deviceName);
    } catch (e) {
      _phase = WebRtcPhase.error;
      _statusError = 'Не удалось подключиться к серверу сигналинга: $e';
      _signalingStatus = 'offline';
      notifyListeners();
    }
  }

  /// Connects using either a WebRTC pairing QR/URL/code OR a local LAN URL.
  Future<bool> connectWithInput(String rawInput) async {
    _statusError = null;
    _notice = null;

    // 1. Try WebRTC pairing secret / URL (`#p=...`, `?p=...`, 24-char code).
    final secret = LuchPairing.parsePairInput(rawInput);
    if (secret != null) {
      await startWebRtcJoin(secret);
      return true;
    }

    // 2. Fallback: local Wi-Fi HTTP session URL (`http://192.168.x.x:port/s/...`).
    final lanUri = ParsedSessionUri.tryParse(rawInput);
    if (lanUri != null) {
      if (!PlatformInfo.supportsLocalLanServer) {
        _statusError =
            'Локальные HTTP-ссылки доступны в нативных приложениях. В браузере используйте QR WebRTC (#p=...).';
        notifyListeners();
        return false;
      }
      return connectToLanUri(lanUri);
    }

    _statusError =
        'Некорректный QR-код или ссылка. Ожидается QR/код «Луч» (24 символа или ссылка #p=...).';
    notifyListeners();
    return false;
  }

  Future<void> startWebRtcJoin(String secret) async {
    await resetWebRtcSession();
    _statusError = null;
    _notice = null;

    await loadServerConfig();
    final normalized = LuchPairing.normalizeSecret(secret);
    final roomId = LuchPairing.roomIdFromSecret(normalized);

    _isHostRole = false;
    _activeSecret = normalized;
    _activePairUrl = null;
    _phase = WebRtcPhase.connecting;
    _signalingStatus = 'connecting';
    _joinRetryAttempts = 0;
    notifyListeners();

    final signaling = SignalingClient(
      url: _buildWsUrl(),
      callbacks: SignalingCallbacks(
        onOpen: () {
          _signalingStatus = 'online';
          notifyListeners();
        },
        onMatched: (peerId, peerDevice, initiator) =>
            _handleMatched(peerDevice, initiator),
        onSignal: (data) => _peer?.handleSignal(data),
        onPeerLeft: _handlePeerLeft,
        onError: _handleSignalingError,
        onClose: (reason) {
          _signalingStatus = 'offline';
          if (_phase == WebRtcPhase.connecting) {
            _phase = WebRtcPhase.error;
            _statusError = reason;
          }
          notifyListeners();
        },
      ),
    );
    _signaling = signaling;

    try {
      await signaling.connect();
      signaling.join(roomId, normalized, _settings.deviceName);
    } catch (e) {
      _phase = WebRtcPhase.error;
      _statusError = 'Не удалось подключиться к серверу сигналинга: $e';
      _signalingStatus = 'offline';
      notifyListeners();
    }
  }

  Future<void> _handleMatched(String peerDevice, bool initiator) async {
    _joinRetryTimer?.cancel();
    _peerName = peerDevice;
    _phase = WebRtcPhase.connecting;
    notifyListeners();

    final secret = _activeSecret;
    final signaling = _signaling;
    if (secret == null || signaling == null) return;

    final peer = PeerSession(
      isHost: initiator,
      secret: secret,
      deviceName: _settings.deviceName,
      deviceId: _settings.deviceId,
      iceServers: _iceServers,
      sendSignal: (payload) => signaling.sendSignal(payload),
      onReady: (link, verifiedPeerName, peerDeviceId) =>
          _handlePeerReady(link, verifiedPeerName, peerDeviceId),
      onError: (err) {
        _phase = WebRtcPhase.error;
        _statusError = err.toString();
        notifyListeners();
      },
    );
    _peer = peer;
    await peer.initialize();
  }

  Future<void> _handlePeerReady(
    PeerDataLink link,
    String verifiedPeerName,
    String peerDeviceId,
  ) async {
    _peerName = verifiedPeerName;
    final secret = _activeSecret;
    if (secret != null) {
      _upsertPairedDevice(
        peerDeviceId: peerDeviceId,
        name: verifiedPeerName,
        secret: secret,
      );
    }

    final session = TransferSession(
      link: link,
      peerName: verifiedPeerName,
      callbacks: TransferCallbacks(
        senderName: _settings.deviceName,
        createIncomingSink: (entry) => PlatformFileStorage.createIncomingSink(
          entry,
          customDirectoryPath: _settings.customSaveDirectory,
        ),
        onOffer: (manifest) {
          _pendingOffer = manifest;
          if (_settings.autoAccept) {
            unawaited(acceptIncomingOffer());
          } else {
            notifyListeners();
          }
        },
        onProgress: _handleProgress,
        onFinished: (results, cancelled) {
          for (final entry in results) {
            _history.insert(0, entry);
          }
          if (cancelled) {
            _phase = WebRtcPhase.connected;
            _notice = 'Передача отменена';
          } else {
            _phase = WebRtcPhase.done;
          }
          notifyListeners();
        },
        onText: (text) {
          _incomingText = text;
          _history.insert(
            0,
            TransferHistoryEntry(
              id: 'txt_${DateTime.now().microsecondsSinceEpoch}',
              fileName: 'Текст (${text.length} симв.)',
              sizeBytes: text.length,
              direction: TransferDirection.received,
              peerName: verifiedPeerName,
              timestamp: DateTime.now(),
              success: true,
            ),
          );
          _phase = WebRtcPhase.done;
          notifyListeners();
        },
        onPaired: (devName) {
          _notice = 'Устройство «$devName» сохранено';
          _phase = WebRtcPhase.connected;
          notifyListeners();
        },
        onError: (err) {
          _phase = WebRtcPhase.error;
          _statusError = err.toString();
          notifyListeners();
        },
      ),
    );
    _transfer = session;
    _phase = WebRtcPhase.connected;
    notifyListeners();

    // Auto-start queued payload if we are the host who initiated Send!
    if (_isHostRole) {
      if (_sendMode == SendContentMode.text && _draftText.trim().isNotEmpty) {
        await sendTextInActiveSession(_draftText);
      } else if (_sendMode == SendContentMode.files && _queuedFiles.isNotEmpty) {
        await sendFilesInActiveSession(List.from(_queuedFiles));
      } else {
        await session.sendPaired(_settings.deviceName);
      }
    }
  }

  Future<void> acceptIncomingOffer() async {
    final session = _transfer;
    if (session == null || _pendingOffer == null) return;
    _pendingOffer = null;
    _phase = WebRtcPhase.transferring;
    notifyListeners();
    await session.acceptOffer();
  }

  Future<void> rejectIncomingOffer() async {
    final session = _transfer;
    _pendingOffer = null;
    notifyListeners();
    await session?.rejectOffer();
  }

  Future<void> sendFilesInActiveSession(List<OutgoingFileSource> files) async {
    final session = _transfer;
    if (session == null || files.isEmpty) return;
    _phase = WebRtcPhase.transferring;
    _statusError = null;
    notifyListeners();
    try {
      await session.sendFiles(files);
    } catch (e) {
      _phase = WebRtcPhase.error;
      _statusError = e.toString();
      notifyListeners();
    }
  }

  Future<void> sendTextInActiveSession(String text) async {
    final session = _transfer;
    if (session == null || text.trim().isEmpty) return;
    _phase = WebRtcPhase.transferring;
    _statusError = null;
    notifyListeners();
    try {
      await session.sendText(text);
      _history.insert(
        0,
        TransferHistoryEntry(
          id: 'txt_${DateTime.now().microsecondsSinceEpoch}',
          fileName: 'Текст (${text.trim().length} симв.)',
          sizeBytes: text.trim().length,
          direction: TransferDirection.sent,
          peerName: _peerName ?? 'Устройство',
          timestamp: DateTime.now(),
          success: true,
        ),
      );
      _phase = WebRtcPhase.done;
      _notice = 'Текст доставлен';
    } catch (e) {
      _phase = WebRtcPhase.error;
      _statusError = e.toString();
    }
    notifyListeners();
  }

  Future<void> cancelActiveTransfer() async {
    await _transfer?.cancel();
  }

  void _handlePeerLeft(String reason) {
    _peer?.close();
    _peer = null;
    _transfer?.dispose(reason);
    _transfer = null;
    if (_phase == WebRtcPhase.transferring) {
      _phase = WebRtcPhase.error;
      _statusError = reason;
    } else if (_phase == WebRtcPhase.done) {
      _notice = 'Второе устройство отключилось';
      _peerName = null;
    } else {
      _phase = WebRtcPhase.idle;
      _notice = reason;
      _peerName = null;
    }
    notifyListeners();
  }

  void _handleSignalingError(String code, String message) {
    if (code == 'room-not-found' &&
        !_isHostRole &&
        _phase == WebRtcPhase.connecting &&
        _joinRetryAttempts < 8 &&
        _activeSecret != null) {
      _joinRetryAttempts++;
      _joinRetryTimer?.cancel();
      _joinRetryTimer = Timer(
        Duration(milliseconds: 250 + _joinRetryAttempts * 200),
        () {
          final sec = _activeSecret;
          if (sec != null && _signaling != null) {
            _signaling!.join(
              LuchPairing.roomIdFromSecret(sec),
              sec,
              _settings.deviceName,
            );
          }
        },
      );
      return;
    }

    const friendly = {
      'room-not-found':
          'Код не найден или уже использован. Попросите показать новый QR.',
      'room-full': 'К этой комнате уже подключились.',
      'room-exists': 'Комната уже существует, попробуйте ещё раз.',
      'forbidden': 'Не удалось подтвердить секрет. Отсканируйте QR заново.',
      'rate-limited': 'Слишком много попыток. Подождите минуту.',
      'server-busy': 'Сервер перегружен. Попробуйте позже.',
      'room-expired': 'Время ожидания истекло. Создайте новый QR.',
    };
    _phase = WebRtcPhase.error;
    _statusError = friendly[code] ?? message;
    _signalingStatus = 'offline';
    notifyListeners();
  }

  // --- Presence 1-tap connect to paired devices ---

  Future<void> connectToPairedDevice(PairedDevice device) async {
    final presence = _presence;
    if (presence == null || _presenceStatus != 'online') {
      _statusError =
          'Канал присутствия не подключён. Проверьте интернет и откройте приложение на втором устройстве.';
      notifyListeners();
      return;
    }

    await resetWebRtcSession();
    _statusError = null;
    _notice = 'Вызываем «${device.name}»...';
    _phase = WebRtcPhase.connecting;
    _isHostRole = true;
    _activeSecret = device.secret;
    notifyListeners();

    final callId = const Uuid().v4();
    _outgoingCallId = callId;
    _outgoingCallTimer?.cancel();
    _outgoingCallTimer = Timer(const Duration(seconds: 25), () {
      if (_outgoingCallId == callId) {
        _outgoingCallId = null;
        _phase = WebRtcPhase.error;
        _statusError = 'Устройство «${device.name}» не ответило.';
        notifyListeners();
      }
    });

    presence.call(
      pairId: device.pairId,
      callId: callId,
      toDeviceId: device.id.startsWith('pair:') ? null : device.id,
    );
  }

  void _handleIncomingCall(IncomingCallEvent event) {
    PairedDevice? match;
    for (final d in _devices) {
      if (d.pairId == event.pairId) {
        match = d;
        break;
      }
    }
    if (match == null) return;

    if (_settings.autoAccept && _phase == WebRtcPhase.idle) {
      _presence?.replyCall(callId: event.callId, accepted: true);
      unawaited(startWebRtcJoin(match.secret));
      return;
    }
    _incomingCall = event;
    notifyListeners();
  }

  Future<void> acceptIncomingCall() async {
    final call = _incomingCall;
    if (call == null) return;
    _incomingCall = null;
    PairedDevice? match;
    for (final d in _devices) {
      if (d.pairId == call.pairId) {
        match = d;
        break;
      }
    }
    _presence?.replyCall(callId: call.callId, accepted: match != null);
    notifyListeners();
    if (match != null) {
      await startWebRtcJoin(match.secret);
    }
  }

  void rejectIncomingCall() {
    final call = _incomingCall;
    if (call == null) return;
    _incomingCall = null;
    _presence?.replyCall(
      callId: call.callId,
      accepted: false,
      reason: 'Отклонено пользователем',
    );
    notifyListeners();
  }

  void _handleCallResult(String callId, int delivered) {
    if (_outgoingCallId != callId) return;
    if (delivered == 0) {
      _outgoingCallTimer?.cancel();
      _outgoingCallId = null;
      _phase = WebRtcPhase.error;
      _statusError =
          'Второе устройство сейчас не в сети (откройте «Луч» на нём).';
      notifyListeners();
    }
  }

  void _handleCallReply(String callId, bool accepted, String? reason) {
    if (_outgoingCallId != callId) return;
    _outgoingCallTimer?.cancel();
    _outgoingCallId = null;
    if (!accepted) {
      _phase = WebRtcPhase.idle;
      _notice = reason ?? 'Вызов отклонён';
      notifyListeners();
      return;
    }
    final secret = _activeSecret;
    if (secret != null) {
      unawaited(_hostWithExistingSecret(secret));
    }
  }

  Future<void> _hostWithExistingSecret(String secret) async {
    await loadServerConfig();
    final roomId = LuchPairing.roomIdFromSecret(secret);
    final signaling = SignalingClient(
      url: _buildWsUrl(),
      callbacks: SignalingCallbacks(
        onOpen: () {
          _signalingStatus = 'online';
          notifyListeners();
        },
        onHosted: (expiresAt) {
          _expiresAtMs = expiresAt;
          notifyListeners();
        },
        onMatched: (peerId, peerDevice, initiator) =>
            _handleMatched(peerDevice, initiator),
        onSignal: (data) => _peer?.handleSignal(data),
        onPeerLeft: _handlePeerLeft,
        onError: _handleSignalingError,
      ),
    );
    _signaling = signaling;
    await signaling.connect();
    signaling.host(roomId, secret, _settings.deviceName);
  }

  Future<void> resetWebRtcSession() async {
    _joinRetryTimer?.cancel();
    _outgoingCallTimer?.cancel();
    _outgoingCallId = null;
    _pendingOffer = null;
    _activeSecret = null;
    _activePairUrl = null;
    _expiresAtMs = null;
    _peerName = null;
    _signalingStatus = 'offline';
    _phase = WebRtcPhase.idle;

    final t = _transfer;
    final p = _peer;
    final s = _signaling;
    _transfer = null;
    _peer = null;
    _signaling = null;
    t?.dispose('Сессия завершена');
    await p?.close();
    await s?.close();
    notifyListeners();
  }

  // --- Optional Local Wi-Fi Direct LAN mode (native platforms) ---

  Future<void> refreshLanInterfaces() async {
    if (!PlatformInfo.supportsLocalLanServer) return;
    _lanInterfaces = await _lanBridge.listInterfaces();
    if (_lanInterfaces.isEmpty) {
      _selectedLanInterface = null;
    } else if (_selectedLanInterface == null ||
        !_lanInterfaces.contains(_selectedLanInterface)) {
      _selectedLanInterface = _lanInterfaces.first;
    }
    notifyListeners();
  }

  void selectLanInterface(LanAddress iface) {
    _selectedLanInterface = iface;
    notifyListeners();
  }

  Future<void> startLanSend() async {
    _statusError = null;
    if (_queuedFiles.isEmpty) {
      _statusError = 'Выберите файлы для локальной раздачи.';
      notifyListeners();
      return;
    }
    await refreshLanInterfaces();
    if (_selectedLanInterface == null) {
      _statusError = 'Не найден локальный IP Wi-Fi.';
      notifyListeners();
      return;
    }
    await _lanBridge.startSendSession(_queuedFiles);
    notifyListeners();
  }

  Future<void> startLanReceiveHost() async {
    _statusError = null;
    await refreshLanInterfaces();
    if (_selectedLanInterface == null) {
      _statusError = 'Не найден локальный IP Wi-Fi.';
      notifyListeners();
      return;
    }
    await _lanBridge.startReceiveSession(
      customSaveDirectory: _settings.customSaveDirectory,
    );
    notifyListeners();
  }

  Future<void> stopLanServer() async {
    await _lanBridge.stop();
    notifyListeners();
  }

  Future<bool> connectToLanUri(ParsedSessionUri uri) async {
    try {
      final session = await _lanBridge.fetchSession(uri);
      _connectedLanUri = uri;
      _connectedLanSession = session;
      notifyListeners();
      return true;
    } catch (e) {
      _statusError = 'Не удалось подключиться к ${uri.host}:${uri.port}: $e';
      notifyListeners();
      return false;
    }
  }

  void disconnectLanPeer() {
    _connectedLanUri = null;
    _connectedLanSession = null;
    notifyListeners();
  }

  Future<void> downloadLanFiles(List<SharedFileItem> files) async {
    final uri = _connectedLanUri;
    final session = _connectedLanSession;
    if (uri == null || session == null) return;
    _isLanTransferring = true;
    notifyListeners();
    try {
      for (final file in files) {
        final savedPath = await _lanBridge.downloadFile(
          sessionUri: uri,
          file: file,
          peerName: session.deviceName,
          customSaveDirectory: _settings.customSaveDirectory,
          onProgress: _handleProgress,
        );
        _handleHistory(
          TransferHistoryEntry(
            id: 'lan_${DateTime.now().microsecondsSinceEpoch}',
            fileName: file.name,
            sizeBytes: file.sizeBytes,
            direction: TransferDirection.received,
            peerName: session.deviceName,
            timestamp: DateTime.now(),
            success: true,
            localPath: savedPath,
          ),
        );
      }
    } catch (e) {
      _statusError = e.toString();
    } finally {
      _isLanTransferring = false;
      notifyListeners();
    }
  }

  Future<void> uploadLanFiles(List<OutgoingFileSource> files) async {
    final uri = _connectedLanUri;
    final session = _connectedLanSession;
    if (uri == null || session == null) return;
    _isLanTransferring = true;
    notifyListeners();
    try {
      await _lanBridge.uploadFiles(
        sessionUri: uri,
        files: files,
        peerName: session.deviceName,
        onProgress: _handleProgress,
      );
      for (final f in files) {
        _handleHistory(
          TransferHistoryEntry(
            id: 'lan_up_${DateTime.now().microsecondsSinceEpoch}',
            fileName: f.name,
            sizeBytes: f.size,
            direction: TransferDirection.sent,
            peerName: session.deviceName,
            timestamp: DateTime.now(),
            success: true,
            localPath: f.displayPath,
          ),
        );
      }
    } catch (e) {
      _statusError = e.toString();
    } finally {
      _isLanTransferring = false;
      notifyListeners();
    }
  }

  void _handleProgress(TransferProgress progress) {
    _transfers[progress.transferId] = progress;
    notifyListeners();
  }

  void _handleHistory(TransferHistoryEntry entry) {
    _history.insert(0, entry);
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _presence?.dispose();
    unawaited(_lanBridge.stop());
    unawaited(resetWebRtcSession());
    super.dispose();
  }
}

extension on String {
  String sliceSafe(int maxLength) =>
      length > maxLength ? substring(0, maxLength) : this;
}
