import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../protocol/transfer_models.dart';

const int luchProtocolVersion = 1;
const int luchChunkSize = 64 * 1024;
const int luchFrameData = 0x01;
const int luchFrameHeaderBytes = 9;
const int luchMaxTextLength = 100000;

class LuchLimits {
  static const int maxEntries = 2000;
  static const int maxEntryBytes = 64 * 1024 * 1024 * 1024;
  static const int maxTotalBytes = 200 * 1024 * 1024 * 1024;
  static const int maxNameLength = 180;
  static const int maxPathDepth = 10;
}

class DecodedDataFrame {
  const DecodedDataFrame({
    required this.fileId,
    required this.seq,
    required this.payload,
  });

  final int fileId;
  final int seq;
  final Uint8List payload;
}

Uint8List encodeDataFrame(int fileId, int seq, Uint8List payload) {
  final frame = Uint8List(luchFrameHeaderBytes + payload.length);
  frame[0] = luchFrameData;
  final view = ByteData.sublistView(frame);
  view.setUint32(1, fileId, Endian.big);
  view.setUint32(5, seq, Endian.big);
  frame.setRange(luchFrameHeaderBytes, frame.length, payload);
  return frame;
}

DecodedDataFrame decodeDataFrame(Uint8List bytes) {
  if (bytes.length < luchFrameHeaderBytes) {
    throw FormatException('Кадр короче заголовка: ${bytes.length} байт');
  }
  if (bytes[0] != luchFrameData) {
    throw FormatException('Неизвестный тип кадра: ${bytes[0]}');
  }
  final view = ByteData.sublistView(bytes);
  return DecodedDataFrame(
    fileId: view.getUint32(1, Endian.big),
    seq: view.getUint32(5, Endian.big),
    payload: Uint8List.sublistView(bytes, luchFrameHeaderBytes),
  );
}

class ManifestFileEntry {
  const ManifestFileEntry({
    required this.id,
    required this.name,
    required this.size,
    required this.type,
    this.relativePath,
    this.lastModified,
  });

  final int id;
  final String name;
  final int size;
  final String type;
  final String? relativePath;
  final int? lastModified;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'type': type,
        if (relativePath != null) 'relativePath': relativePath,
        if (lastModified != null) 'lastModified': lastModified,
      };
}

class TransferManifest {
  const TransferManifest({
    required this.transferId,
    required this.senderName,
    required this.entries,
    required this.totalBytes,
    required this.createdAt,
  });

  final String transferId;
  final String senderName;
  final List<ManifestFileEntry> entries;
  final int totalBytes;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'transferId': transferId,
        'senderName': senderName,
        'entries': entries.map((e) => e.toJson()).toList(),
        'totalBytes': totalBytes,
        'createdAt': createdAt,
      };

  static TransferManifest create({
    required String senderName,
    required List<OutgoingFileDescriptor> files,
  }) {
    if (files.isEmpty) {
      throw ArgumentError('Нечего отправлять: пустой список файлов');
    }
    if (files.length > LuchLimits.maxEntries) {
      throw ArgumentError(
          'Слишком много файлов: максимум ${LuchLimits.maxEntries}');
    }
    final entries = <ManifestFileEntry>[];
    var total = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final safeName = sanitizeFileName(f.name);
      entries.add(
        ManifestFileEntry(
          id: i + 1,
          name: safeName,
          size: f.size,
          type: f.mimeType ?? guessMimeType(safeName),
          relativePath: f.relativePath != null
              ? sanitizeRelativePath(f.relativePath!)
              : null,
          lastModified: f.lastModified,
        ),
      );
      total += f.size;
    }
    return TransferManifest(
      transferId: const Uuid().v4(),
      senderName: senderName.length > 80
          ? senderName.substring(0, 80)
          : (senderName.isEmpty ? 'Устройство' : senderName),
      entries: entries,
      totalBytes: total,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static TransferManifest validate(Map<String, dynamic> raw) {
    final entriesRaw = raw['entries'];
    if (entriesRaw is! List || entriesRaw.isEmpty) {
      throw const FormatException('Пустой манифест');
    }
    if (entriesRaw.length > LuchLimits.maxEntries) {
      throw const FormatException('Слишком много файлов в манифесте');
    }
    final seen = <int>{};
    final entries = <ManifestFileEntry>[];
    var totalBytes = 0;

    for (final item in entriesRaw) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Некорректная запись файла');
      }
      final id = item['id'];
      final size = item['size'];
      final name = item['name'];
      if (id is! int || id < 1 || id > 0xffffffff) {
        throw const FormatException('Некорректный id файла');
      }
      if (!seen.add(id)) {
        throw const FormatException('Повторяющийся id файла');
      }
      if (size is! int || size < 0 || size > LuchLimits.maxEntryBytes) {
        throw const FormatException('Некорректный размер файла');
      }
      if (name is! String || name.isEmpty) {
        throw const FormatException('Некорректное имя файла');
      }
      final safeName = sanitizeFileName(name);
      final rawType = item['type'];
      final type = rawType is String && rawType.isNotEmpty
          ? (rawType.length > 120 ? rawType.substring(0, 120) : rawType)
          : guessMimeType(safeName);
      final rel = item['relativePath'];
      final safeRel = rel is String ? sanitizeRelativePath(rel) : null;
      final lm = item['lastModified'];

      totalBytes += size;
      if (totalBytes > LuchLimits.maxTotalBytes) {
        throw const FormatException('Слишком большой суммарный размер');
      }
      entries.add(
        ManifestFileEntry(
          id: id,
          name: safeName,
          size: size,
          type: type,
          relativePath: safeRel,
          lastModified: lm is int ? lm : null,
        ),
      );
    }

    final rawId = raw['transferId'];
    if (rawId is! String || rawId.isEmpty) {
      throw const FormatException('Манифест без transferId');
    }
    final transferId = rawId.length > 64 ? rawId.substring(0, 64) : rawId;
    final rawSender = raw['senderName'];
    final senderName = rawSender is String && rawSender.isNotEmpty
        ? (rawSender.length > 80 ? rawSender.substring(0, 80) : rawSender)
        : 'Устройство';
    final createdAt = raw['createdAt'];

    return TransferManifest(
      transferId: transferId,
      senderName: senderName,
      entries: entries,
      totalBytes: totalBytes,
      createdAt:
          createdAt is int ? createdAt : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class OutgoingFileDescriptor {
  const OutgoingFileDescriptor({
    required this.name,
    required this.size,
    this.mimeType,
    this.relativePath,
    this.lastModified,
  });

  final String name;
  final int size;
  final String? mimeType;
  final String? relativePath;
  final int? lastModified;
}

String? sanitizeRelativePath(String input) {
  final segments = input
      .split(RegExp(r'[\\/]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s != '.' && s != '..')
      .toList();
  if (segments.isEmpty) return null;
  final limited = segments.length > LuchLimits.maxPathDepth
      ? segments.sublist(segments.length - LuchLimits.maxPathDepth)
      : segments;
  return limited.map(sanitizeFileName).join('/');
}

String guessMimeType(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
  final ext = name.substring(dot + 1).toLowerCase();
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'svg': 'image/svg+xml',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'wav': 'audio/wav',
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'json': 'application/json',
    'csv': 'text/csv',
    'html': 'text/html',
    'apk': 'application/vnd.android.package-archive',
    'dmg': 'application/x-apple-diskimage',
    'exe': 'application/vnd.microsoft.portable-executable',
  };
  return map[ext] ?? 'application/octet-stream';
}
