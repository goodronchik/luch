import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class IncomingCallEvent {
  const IncomingCallEvent({
    required this.callId,
    required this.pairId,
    required this.fromDevice,
    required this.fromDeviceId,
  });

  final String callId;
  final String pairId;
  final String fromDevice;
  final String fromDeviceId;
}

class PresenceCallbacks {
  const PresenceCallbacks({
    this.onStateChange,
    this.onIncomingCall,
    this.onCallResult,
    this.onCallReply,
  });

  final void Function(String status)? onStateChange; // offline, connecting, online
  final void Function(IncomingCallEvent event)? onIncomingCall;
  final void Function(String callId, int delivered)? onCallResult;
  final void Function(String callId, bool accepted, String? reason)? onCallReply;
}

/// Persistent presence WebSocket for 1-tap connect between paired devices.
class PresenceClient {
  PresenceClient({
    required this.url,
    required this.deviceId,
    required this.deviceName,
    required this.callbacks,
  });

  String url;
  final String deviceId;
  String deviceName;
  final PresenceCallbacks callbacks;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  List<String> _pairs = const [];
  bool _disposed = false;
  int _backoffMs = 1500;

  void updateRegistration({
    required List<String> pairs,
    required String deviceName,
    String? newUrl,
  }) {
    _pairs = List.unmodifiable(pairs);
    this.deviceName = deviceName;
    if (newUrl != null && newUrl != url) {
      url = newUrl;
      _disconnectSocket();
    }

    if (_pairs.isEmpty) {
      _reconnectTimer?.cancel();
      _disconnectSocket();
      callbacks.onStateChange?.call('offline');
      return;
    }

    if (_channel == null) {
      connect();
    } else {
      _sendWatch();
    }
  }

  Future<void> connect() async {
    if (_disposed || _pairs.isEmpty || _channel != null) return;
    _reconnectTimer?.cancel();
    callbacks.onStateChange?.call('connecting');

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 12));
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _backoffMs = 1500;
      callbacks.onStateChange?.call('online');
      _sendWatch();

      _sub = channel.stream.listen(
        (raw) => _handleMessage(raw.toString()),
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
    } catch (_) {
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _disconnectSocket();
    if (_disposed || _pairs.isEmpty) {
      callbacks.onStateChange?.call('offline');
      return;
    }
    callbacks.onStateChange?.call('offline');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _backoffMs), connect);
    _backoffMs = (_backoffMs * 2).clamp(1500, 30000);
  }

  void _sendWatch() {
    _send({
      't': 'watch',
      'pairs': _pairs,
      'deviceId': deviceId,
      'device': deviceName,
    });
  }

  void call({
    required String pairId,
    required String callId,
    String? toDeviceId,
  }) {
    final payload = <String, dynamic>{
      't': 'call',
      'pairId': pairId,
      'callId': callId,
      'device': deviceName,
    };
    if (toDeviceId != null && toDeviceId.isNotEmpty) {
      payload['toDeviceId'] = toDeviceId;
    }
    _send(payload);
  }

  void replyCall({
    required String callId,
    required bool accepted,
    String? reason,
  }) {
    _send({
      't': 'call-reply',
      'callId': callId,
      'accepted': accepted,
      'reason': ?reason,
    });
  }

  void _send(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (_) {}
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
      case 'call':
        final callId = decoded['callId'];
        final pairId = decoded['pairId'];
        final fromDevice = decoded['fromDevice'];
        final fromDeviceId = decoded['fromDeviceId'];
        if (callId is String &&
            pairId is String &&
            fromDevice is String) {
          callbacks.onIncomingCall?.call(
            IncomingCallEvent(
              callId: callId,
              pairId: pairId,
              fromDevice: fromDevice,
              fromDeviceId: fromDeviceId is String ? fromDeviceId : '',
            ),
          );
        }
      case 'call-result':
        final callId = decoded['callId'];
        final delivered = decoded['delivered'];
        if (callId is String && delivered is num) {
          callbacks.onCallResult?.call(callId, delivered.toInt());
        }
      case 'call-reply':
        final callId = decoded['callId'];
        final accepted = decoded['accepted'];
        final reason = decoded['reason'];
        if (callId is String && accepted is bool) {
          callbacks.onCallReply?.call(
            callId,
            accepted,
            reason is String ? reason : null,
          );
        }
    }
  }

  void _disconnectSocket() {
    _sub?.cancel();
    _sub = null;
    final ch = _channel;
    _channel = null;
    ch?.sink.close();
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _disconnectSocket();
  }
}
