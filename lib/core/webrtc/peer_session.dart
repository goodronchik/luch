import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'luch_crypto.dart';
import 'transfer_protocol.dart';

/// Bidirectional channel abstraction over WebRTC DataChannel.
class PeerDataLink {
  PeerDataLink(this._channel);

  final RTCDataChannel _channel;

  void Function(String text)? onText;
  void Function(Uint8List data)? onBinary;
  void Function(String reason)? onClose;

  void attachHandlers() {
    _channel.onMessage = (msg) {
      if (msg.isBinary) {
        onBinary?.call(msg.binary);
      } else {
        onText?.call(msg.text);
      }
    };
    _channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed ||
          state == RTCDataChannelState.RTCDataChannelClosing) {
        onClose?.call('Канал передачи закрыт');
      }
    };
  }

  Future<void> sendText(String text) async {
    await _channel.send(RTCDataChannelMessage(text));
  }

  Future<void> sendBinary(Uint8List bytes) async {
    await _channel.send(RTCDataChannelMessage.fromBinary(bytes));
  }

  Future<void> waitForDrain(int lowWaterBytes, {bool Function()? isAborted}) async {
    while (true) {
      if (isAborted?.call() ?? false) {
        throw StateError('Передача отменена');
      }
      int buffered;
      try {
        buffered = await _channel.getBufferedAmount();
      } catch (_) {
        buffered = _channel.bufferedAmount ?? 0;
      }
      if (buffered <= lowWaterBytes) return;
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
  }

  Future<void> close() async {
    try {
      await _channel.close();
    } catch (_) {}
  }
}

/// Manages RTCPeerConnection + DTLS fingerprint HMAC channel authentication.
class PeerSession {
  PeerSession({
    required this.isHost,
    required this.secret,
    required this.deviceName,
    required this.deviceId,
    required this.iceServers,
    required this.sendSignal,
    required this.onReady,
    required this.onError,
  });

  final bool isHost;
  final String secret;
  final String deviceName;
  final String deviceId;
  final List<Map<String, dynamic>> iceServers;
  final void Function(Map<String, dynamic> payload) sendSignal;
  final void Function(PeerDataLink link, String peerName, String peerDeviceId)
      onReady;
  final void Function(Object error) onError;

  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;
  PeerDataLink? _link;
  Timer? _authTimer;
  final List<RTCIceCandidate> _pendingCandidates = [];

  String _peerName = 'Устройство';
  String _peerDeviceId = '';
  String _localFp = '';
  String _remoteFp = '';
  bool _peerHelloReceived = false;
  bool _authSent = false;
  bool _verified = false;
  bool _peerVerifiedUs = false;
  bool _handedOff = false;
  bool _disposed = false;

  Future<void> initialize() async {
    final config = <String, dynamic>{
      'iceServers': iceServers,
      'bundlePolicy': 'max-bundle',
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(config);
    _pc = pc;

    pc.onIceCandidate = (candidate) {
      if (_disposed || candidate.candidate == null) return;
      try {
        sendSignal({
          'kind': 'candidate',
          'candidate': candidate.toMap(),
        });
      } catch (_) {}
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _fail(StateError('Не удалось установить прямое соединение'));
      }
    };

    pc.onDataChannel = (channel) {
      if (channel.label == 'luch') {
        _attachChannel(channel);
      }
    };

    if (isHost) {
      final init = RTCDataChannelInit()..ordered = true;
      final channel = await pc.createDataChannel('luch', init);
      _attachChannel(channel);
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      final local = await pc.getLocalDescription() ?? offer;
      sendSignal({
        'kind': 'description',
        'description': local.toMap(),
      });
    }
  }

  Future<void> handleSignal(dynamic raw) async {
    if (_disposed || raw is! Map<String, dynamic>) return;
    final pc = _pc;
    if (pc == null) return;

    final kind = raw['kind'];
    if (kind == 'candidate') {
      final candMap = raw['candidate'];
      if (candMap is! Map<String, dynamic>) return;
      final candidate = RTCIceCandidate(
        candMap['candidate'] as String?,
        candMap['sdpMid'] as String?,
        (candMap['sdpMLineIndex'] as num?)?.toInt(),
      );
      if (await pc.getRemoteDescription() != null) {
        await pc.addCandidate(candidate).catchError((_) {});
      } else {
        _pendingCandidates.add(candidate);
      }
      return;
    }

    if (kind == 'description') {
      final descMap = raw['description'];
      if (descMap is! Map<String, dynamic>) return;
      final type = descMap['type'] as String?;
      final sdp = descMap['sdp'] as String?;
      if (type == null || sdp == null) return;

      if (type == 'offer' && !isHost) {
        await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
        await _flushCandidates();
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        final local = await pc.getLocalDescription() ?? answer;
        sendSignal({
          'kind': 'description',
          'description': local.toMap(),
        });
      } else if (type == 'answer' && isHost) {
        await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
        await _flushCandidates();
      }
    }
  }

  Future<void> _flushCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    final list = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final c in list) {
      await pc.addCandidate(c).catchError((_) {});
    }
  }

  void _attachChannel(RTCDataChannel channel) {
    _channel = channel;
    final link = PeerDataLink(channel);
    _link = link;

    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _onChannelOpen();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed &&
          !_handedOff &&
          !_disposed) {
        _fail(StateError('Канал передачи закрыт'));
      }
    };

    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      _onChannelOpen();
    }
  }

  Future<void> _onChannelOpen() async {
    if (_disposed || _handedOff || _link == null) return;
    final pc = _pc;
    if (pc == null) return;

    final localDesc = await pc.getLocalDescription();
    final remoteDesc = await pc.getRemoteDescription();
    final localSdp = localDesc?.sdp;
    final remoteSdp = remoteDesc?.sdp;
    if (localSdp == null || remoteSdp == null) {
      _fail(StateError('SDP ещё не готов — нечего проверять'));
      return;
    }

    try {
      _localFp = LuchCrypto.normalizeDtlsFingerprint(localSdp);
      _remoteFp = LuchCrypto.normalizeDtlsFingerprint(remoteSdp);
    } catch (e) {
      _fail(e);
      return;
    }

    final link = _link!;
    link.onText = _handleAuthText;
    link.onClose = (reason) {
      if (!_disposed && !_handedOff) {
        _fail(StateError(reason));
      }
    };
    link.attachHandlers();

    _authTimer?.cancel();
    _authTimer = Timer(const Duration(seconds: 20), () {
      _fail(TimeoutException('Не удалось подтвердить канал за 20 секунд'));
    });

    await link.sendText(
      jsonEncode({
        't': 'hello',
        'v': luchProtocolVersion,
        'device': deviceName,
        'fp': _localFp,
        'deviceId': deviceId,
      }),
    );
    await _maybeSendAuth();
  }

  void _handleAuthText(String raw) {
    if (_disposed) return;
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    switch (decoded['t']) {
      case 'hello':
        if (decoded['v'] != luchProtocolVersion) {
          _fail(StateError('Версии протокола не совпадают. Обновите приложение.'));
          return;
        }
        final fp = (decoded['fp'] as String? ?? '').toLowerCase();
        if (fp.isEmpty || fp != _remoteFp) {
          _fail(StateError('Отпечаток канала не совпал: соединение перехвачено'));
          return;
        }
        final dev = decoded['device'] as String? ?? 'Устройство';
        _peerName = dev.isEmpty ? 'Устройство' : dev;
        _peerDeviceId = decoded['deviceId'] as String? ?? '';
        _peerHelloReceived = true;
        _maybeSendAuth();
      case 'auth':
        final tag = decoded['tag'] as String? ?? '';
        _verifyPeerTag(tag);
      case 'auth-ok':
        _peerVerifiedUs = true;
        _maybeHandOff();
      case 'auth-fail':
        _fail(StateError('Секрет сопряжения не подошёл'));
    }
  }

  Future<void> _maybeSendAuth() async {
    if (_authSent || !_peerHelloReceived || _link == null || _disposed) return;
    _authSent = true;
    final hostFp = isHost ? _localFp : _remoteFp;
    final joinFp = isHost ? _remoteFp : _localFp;
    try {
      final tag = LuchCrypto.channelAuthTag(secret, hostFp, joinFp);
      await _link!.sendText(jsonEncode({'t': 'auth', 'tag': tag}));
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _verifyPeerTag(String tag) async {
    if (_link == null || _disposed) return;
    final hostFp = isHost ? _localFp : _remoteFp;
    final joinFp = isHost ? _remoteFp : _localFp;
    final ok = LuchCrypto.verifyChannelAuthTag(secret, hostFp, joinFp, tag);
    if (!ok) {
      await _link!
          .sendText(jsonEncode({'t': 'auth-fail', 'reason': 'Тег не совпал'}));
      _fail(StateError('Второе устройство не подтвердило секрет сопряжения'));
      return;
    }
    _verified = true;
    await _link!.sendText(jsonEncode({'t': 'auth-ok'}));
    _maybeHandOff();
  }

  void _maybeHandOff() {
    if (_handedOff || !_verified || !_peerVerifiedUs || _link == null) return;
    _handedOff = true;
    _authTimer?.cancel();
    _authTimer = null;
    onReady(_link!, _peerName, _peerDeviceId);
  }

  void _fail(Object error) {
    if (_disposed) return;
    _disposed = true;
    _authTimer?.cancel();
    _closeResources();
    onError(error);
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _authTimer?.cancel();
    await _closeResources();
  }

  Future<void> _closeResources() async {
    try {
      await _channel?.close();
    } catch (_) {}
    try {
      await _pc?.close();
      await _pc?.dispose();
    } catch (_) {}
    _channel = null;
    _pc = null;
  }
}
