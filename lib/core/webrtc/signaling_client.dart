import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'base32.dart';
import 'luch_crypto.dart';

class SignalingCallbacks {
  const SignalingCallbacks({
    this.onOpen,
    this.onHosted,
    this.onMatched,
    this.onSignal,
    this.onPeerLeft,
    this.onError,
    this.onClose,
  });

  final void Function()? onOpen;
  final void Function(int expiresAt)? onHosted;
  final void Function(String peerId, String peerDevice, bool initiator)?
      onMatched;
  final void Function(dynamic data)? onSignal;
  final void Function(String reason)? onPeerLeft;
  final void Function(String code, String message)? onError;
  final void Function(String reason)? onClose;
}

/// WebSocket signaling client compatible with `@luch/signaling` (`/signal`).
class SignalingClient {
  SignalingClient({
    required this.url,
    required this.callbacks,
  });

  final String url;
  final SignalingCallbacks callbacks;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _closedByUs = false;

  Future<void> connect() async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    _channel = channel;
    await channel.ready.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('Сигнальный сервер не отвечает'),
    );

    callbacks.onOpen?.call();

    _sub = channel.stream.listen(
      (raw) => _handleMessage(raw.toString()),
      onError: (_) {
        if (!_closedByUs) {
          callbacks.onClose?.call('Связь с сигнальным сервером потеряна');
        }
      },
      onDone: () {
        if (!_closedByUs) {
          callbacks.onClose?.call('Сигнальный сервер закрыл соединение');
        }
      },
    );
  }

  void host(String roomId, String secret, String deviceName) {
    final normalized = CrockfordBase32.normalize(secret);
    _send({
      't': 'host',
      'roomId': roomId,
      'tokenHash': LuchCrypto.sha256Hex(normalized),
      'device': deviceName,
    });
  }

  void join(String roomId, String secret, String deviceName) {
    final normalized = CrockfordBase32.normalize(secret);
    _send({
      't': 'join',
      'roomId': roomId,
      'tokenHash': LuchCrypto.sha256Hex(normalized),
      'device': deviceName,
    });
  }

  void sendSignal(dynamic data) {
    _send({'t': 'signal', 'data': data});
  }

  void _send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void _handleMessage(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['t']) {
      case 'hosted':
        final expires = decoded['expiresAt'];
        if (expires is num) {
          callbacks.onHosted?.call(expires.toInt());
        }
      case 'matched':
        final peerId = decoded['peerId'];
        final peerDevice = decoded['peerDevice'];
        final initiator = decoded['initiator'];
        if (peerId is String &&
            peerDevice is String &&
            initiator is bool) {
          callbacks.onMatched?.call(peerId, peerDevice, initiator);
        }
      case 'signal':
        callbacks.onSignal?.call(decoded['data']);
      case 'peer-left':
        final reason = decoded['reason'];
        callbacks.onPeerLeft?.call(
          reason is String ? reason : 'Соединение закрыто',
        );
      case 'error':
        final code = decoded['code'];
        final message = decoded['message'];
        callbacks.onError?.call(
          code is String ? code : 'internal',
          message is String ? message : 'Ошибка сигнального сервера',
        );
      case 'pong':
        break;
    }
  }

  Future<void> close() async {
    _closedByUs = true;
    final channel = _channel;
    _channel = null;
    await _sub?.cancel();
    _sub = null;
    if (channel != null) {
      try {
        channel.sink.add(jsonEncode({'t': 'leave'}));
      } catch (_) {}
      await channel.sink.close();
    }
  }
}
