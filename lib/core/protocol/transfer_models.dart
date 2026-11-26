import 'dart:math';

/// Direction of a local transfer session hosted by this device.
enum SessionMode {
  send,
  receive;

  String toWire() => name;

  static SessionMode fromWire(String value) {
    return value == 'receive' ? SessionMode.receive : SessionMode.send;
  }
}

/// Lifecycle state of an individual file transfer.
enum TransferStatus {
  pending,
  transferring,
  completed,
  failed,
}

/// Direction from the perspective of this device for history logging.
enum TransferDirection {
  sent,
  received,
}

/// Metadata describing a file offered in a session.
class SharedFileItem {
  const SharedFileItem({
    required this.id,
    required this.name,
    required this.sizeBytes,
    this.localPath,
    this.mimeType = 'application/octet-stream',
    this.sha256,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final String? localPath;
  final String mimeType;
  final String? sha256;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sizeBytes': sizeBytes,
        'mimeType': mimeType,
        if (sha256 != null) 'sha256': sha256,
      };

  factory SharedFileItem.fromJson(Map<String, dynamic> json) {
    return SharedFileItem(
      id: json['id'] as String? ?? '',
      name: sanitizeFileName(json['name'] as String? ?? 'file.bin'),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      sha256: json['sha256'] as String?,
    );
  }
}

/// Parsed connection details extracted from a QR code or pasted link.
class ParsedSessionUri {
  const ParsedSessionUri({
    required this.host,
    required this.port,
    required this.token,
    required this.baseUri,
  });

  final String host;
  final int port;
  final String token;
  final Uri baseUri;

  Uri apiUri(String path, [Map<String, String>? extraQuery]) {
    return baseUri.replace(
      path: path,
      queryParameters: {
        'token': token,
        ...?extraQuery,
      },
    );
  }

  /// Parses QR payloads like `http://192.168.1.10:54321/s/<token>`.
  static ParsedSessionUri? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    var normalized = trimmed;
    if (normalized.startsWith('luch://')) {
      normalized = 'http://${normalized.substring('luch://'.length)}';
    } else if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty || !uri.hasPort) {
      return null;
    }

    String? token = uri.queryParameters['token'];
    if ((token == null || token.isEmpty) && uri.pathSegments.length >= 2) {
      if (uri.pathSegments[0] == 's') {
        token = uri.pathSegments[1];
      }
    }

    if (token == null || token.length < 8) {
      return null;
    }

    final baseUri = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.port,
    );

    return ParsedSessionUri(
      host: uri.host,
      port: uri.port,
      token: token,
      baseUri: baseUri,
    );
  }
}

/// Session description returned by `/api/v1/session`.
class SessionInfo {
  const SessionInfo({
    required this.sessionId,
    required this.deviceName,
    required this.platform,
    required this.mode,
    required this.files,
  });

  final String sessionId;
  final String deviceName;
  final String platform;
  final SessionMode mode;
  final List<SharedFileItem> files;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'deviceName': deviceName,
        'platform': platform,
        'mode': mode.toWire(),
        'files': files.map((f) => f.toJson()).toList(),
      };

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as List<dynamic>? ?? const [];
    return SessionInfo(
      sessionId: json['sessionId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Устройство',
      platform: json['platform'] as String? ?? 'unknown',
      mode: SessionMode.fromWire(json['mode'] as String? ?? 'send'),
      files: rawFiles
          .whereType<Map<String, dynamic>>()
          .map(SharedFileItem.fromJson)
          .toList(),
    );
  }
}

/// Live progress snapshot for an active or completed transfer.
class TransferProgress {
  const TransferProgress({
    required this.transferId,
    required this.fileName,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.speedBytesPerSec,
    required this.status,
    required this.direction,
    this.peerLabel,
    this.savedPath,
    this.errorMessage,
  });

  final String transferId;
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;
  final double speedBytesPerSec;
  final TransferStatus status;
  final TransferDirection direction;
  final String? peerLabel;
  final String? savedPath;
  final String? errorMessage;

  double get fraction {
    if (totalBytes <= 0) {
      return status == TransferStatus.completed ? 1.0 : 0.0;
    }
    return min(1.0, max(0.0, bytesTransferred / totalBytes));
  }

  TransferProgress copyWith({
    int? bytesTransferred,
    int? totalBytes,
    double? speedBytesPerSec,
    TransferStatus? status,
    String? savedPath,
    String? errorMessage,
  }) {
    return TransferProgress(
      transferId: transferId,
      fileName: fileName,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      status: status ?? this.status,
      direction: direction,
      peerLabel: peerLabel,
      savedPath: savedPath ?? this.savedPath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Persistent in-memory log entry shown in the History tab.
class TransferHistoryEntry {
  const TransferHistoryEntry({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.direction,
    required this.peerName,
    required this.timestamp,
    required this.success,
    this.localPath,
    this.errorMessage,
  });

  final String id;
  final String fileName;
  final int sizeBytes;
  final TransferDirection direction;
  final String peerName;
  final DateTime timestamp;
  final bool success;
  final String? localPath;
  final String? errorMessage;
}

/// Strips directory traversal, control chars, and invalid Windows filename chars.
String sanitizeFileName(String rawName) {
  var name = rawName.replaceAll('\\', '/').split('/').last.trim();
  name = name.replaceAll(RegExp(r'[\x00-\x1F<>:"/\\|?*]'), '_');
  while (name.startsWith('.')) {
    name = name.substring(1);
  }
  if (name.isEmpty || name == '.' || name == '..') {
    return 'file_${DateTime.now().millisecondsSinceEpoch}.bin';
  }
  return name;
}

/// Formats byte count into human-readable units.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes.toDouble();
  var unitIndex = -1;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final decimals = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

/// Formats transfer throughput in human-readable units.
String formatSpeed(double bytesPerSec) {
  if (bytesPerSec <= 0) return '0 Б/с';
  return '${formatBytes(bytesPerSec.round())}/с';
}
