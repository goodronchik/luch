import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../platform/file_io_adapter.dart';
import '../protocol/transfer_models.dart';
import 'peer_session.dart';
import 'transfer_protocol.dart';

class _DigestCaptureSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}

class _IncomingEntryState {
  _IncomingEntryState({required this.entry});

  final ManifestFileEntry entry;
  int bytes = 0;
  int seq = 0;
  final _DigestCaptureSink digestSink = _DigestCaptureSink();
  late final ByteConversionSink hashSink =
      sha256.startChunkedConversion(digestSink);
  IncomingFileSink? fileSink;
  bool closed = false;
}

class TransferCallbacks {
  const TransferCallbacks({
    required this.senderName,
    required this.createIncomingSink,
    this.onOffer,
    this.onProgress,
    this.onFinished,
    this.onError,
    this.onText,
    this.onPaired,
  });

  final String senderName;
  final Future<IncomingFileSink> Function(ManifestFileEntry entry)
      createIncomingSink;
  final void Function(TransferManifest manifest)? onOffer;
  final void Function(TransferProgress progress)? onProgress;
  final void Function(List<TransferHistoryEntry> results, bool cancelled)?
      onFinished;
  final void Function(Object error)? onError;
  final void Function(String text)? onText;
  final void Function(String deviceName)? onPaired;
}

/// Bidirectional file & text transfer session over an authenticated [PeerDataLink].
class TransferSession {
  TransferSession({
    required this.link,
    required this.peerName,
    required this.callbacks,
  }) {
    link.onText = _handleControlText;
    link.onBinary = _handleBinaryFrame;
    link.onClose = (reason) => dispose(reason);
    link.attachHandlers();
  }

  final PeerDataLink link;
  final String peerName;
  final TransferCallbacks callbacks;

  TransferManifest? _pendingOffer;
  Completer<List<int>>? _pendingAccept;
  Completer<void>? _pendingDone;
  Completer<({bool ok, String? reason})>? _pendingTextAck;

  bool _aborted = false;
  bool _disposed = false;
  String? _activeTransferId;
  TransferManifest? _outgoingManifest;
  final Map<int, _IncomingEntryState> _incomingEntries = {};
  final List<TransferHistoryEntry> _incomingOutcomes = [];
  TransferManifest? _incomingManifest;
  Future<void> _writeQueue = Future.value();

  TransferManifest? get pendingOffer => _pendingOffer;

  Future<List<TransferHistoryEntry>> sendFiles(
    List<OutgoingFileSource> sources,
  ) async {
    if (_disposed) throw StateError('Соединение закрыто');
    if (_outgoingManifest != null || _incomingManifest != null) {
      throw StateError('Канал занят другой передачей');
    }

    _aborted = false;
    final descriptors = sources
        .map(
          (s) => OutgoingFileDescriptor(
            name: s.name,
            size: s.size,
            mimeType: s.mimeType,
            relativePath: s.relativePath,
          ),
        )
        .toList();
    final manifest = TransferManifest.create(
      senderName: callbacks.senderName,
      files: descriptors,
    );
    _outgoingManifest = manifest;
    _activeTransferId = manifest.transferId;

    final acceptCompleter = Completer<List<int>>();
    _pendingAccept = acceptCompleter;
    await link.sendText(jsonEncode({'t': 'offer', 'manifest': manifest.toJson()}));

    List<int> acceptedIds;
    try {
      acceptedIds = await acceptCompleter.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () => throw TimeoutException('Получатель не ответил'),
      );
    } finally {
      _pendingAccept = null;
    }

    final accepted = acceptedIds.toSet();
    final doneCompleter = Completer<void>();
    _pendingDone = doneCompleter;
    final history = <TransferHistoryEntry>[];

    try {
      for (var i = 0; i < manifest.entries.length; i++) {
        if (_aborted) throw StateError('Передача отменена');
        final entry = manifest.entries[i];
        final source = sources[i];
        if (!accepted.contains(entry.id)) continue;

        final startedAt = DateTime.now();
        final digestCapture = _DigestCaptureSink();
        final hashSink = sha256.startChunkedConversion(digestCapture);
        var offset = 0;
        var seq = 0;

        while (offset < entry.size) {
          if (_aborted) throw StateError('Передача отменена');
          final end =
              (offset + luchChunkSize > entry.size) ? entry.size : offset + luchChunkSize;
          final chunk = await source.readRange(offset, end);
          await link.waitForDrain(1024 * 1024, isAborted: () => _aborted || _disposed);
          await link.sendBinary(encodeDataFrame(entry.id, seq, chunk));
          hashSink.add(chunk);
          offset = end;
          seq++;

          final elapsedSec =
              (DateTime.now().difference(startedAt).inMilliseconds / 1000.0)
                  .clamp(0.05, 1e9);
          callbacks.onProgress?.call(
            TransferProgress(
              transferId: '${manifest.transferId}_${entry.id}',
              fileName: entry.name,
              bytesTransferred: offset,
              totalBytes: entry.size,
              speedBytesPerSec: offset / elapsedSec,
              status: TransferStatus.transferring,
              direction: TransferDirection.sent,
              peerLabel: peerName,
            ),
          );
        }

        hashSink.close();
        final digestHex = digestCapture.digest?.toString() ?? '';
        await link.sendText(
          jsonEncode({
            't': 'file-end',
            'transferId': manifest.transferId,
            'id': entry.id,
            'size': entry.size,
            'sha256': digestHex,
          }),
        );

        final elapsedSec =
            (DateTime.now().difference(startedAt).inMilliseconds / 1000.0)
                .clamp(0.05, 1e9);
        callbacks.onProgress?.call(
          TransferProgress(
            transferId: '${manifest.transferId}_${entry.id}',
            fileName: entry.name,
            bytesTransferred: entry.size,
            totalBytes: entry.size,
            speedBytesPerSec: entry.size / elapsedSec,
            status: TransferStatus.completed,
            direction: TransferDirection.sent,
            peerLabel: peerName,
          ),
        );

        history.add(
          TransferHistoryEntry(
            id: '${manifest.transferId}_${entry.id}',
            fileName: entry.name,
            sizeBytes: entry.size,
            direction: TransferDirection.sent,
            peerName: peerName,
            timestamp: DateTime.now(),
            success: true,
            localPath: source.displayPath,
          ),
        );
      }

      await doneCompleter.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () {},
      );
      callbacks.onFinished?.call(history, false);
      return history;
    } finally {
      _pendingDone = null;
      _outgoingManifest = null;
      _activeTransferId = null;
    }
  }

  Future<void> acceptOffer([List<int>? ids]) async {
    final manifest = _pendingOffer;
    if (manifest == null) throw StateError('Нет предложения для приёма');
    final selected = ids == null
        ? manifest.entries
        : manifest.entries.where((e) => ids.contains(e.id)).toList();
    if (selected.isEmpty) {
      await rejectOffer('Получатель не выбрал ни одного файла');
      return;
    }

    _pendingOffer = null;
    _aborted = false;
    _incomingManifest = manifest;
    _activeTransferId = manifest.transferId;
    _incomingEntries.clear();
    _incomingOutcomes.clear();

    for (final entry in selected) {
      _incomingEntries[entry.id] = _IncomingEntryState(entry: entry);
    }

    await link.sendText(
      jsonEncode({
        't': 'accept',
        'transferId': manifest.transferId,
        'ids': selected.map((e) => e.id).toList(),
      }),
    );
  }

  Future<void> rejectOffer([String reason = 'Приём отклонён']) async {
    final manifest = _pendingOffer;
    _pendingOffer = null;
    if (manifest != null) {
      await link.sendText(
        jsonEncode({
          't': 'reject',
          'transferId': manifest.transferId,
          'reason': reason,
        }),
      );
    }
  }

  Future<void> sendText(String text) async {
    if (_disposed) throw StateError('Соединение закрыто');
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('Пустой текст');
    if (trimmed.length > luchMaxTextLength) {
      throw ArgumentError('Текст длиннее $luchMaxTextLength символов');
    }

    final transferId = const Uuid().v4();
    final ack = Completer<({bool ok, String? reason})>();
    _pendingTextAck = ack;
    await link.sendText(
      jsonEncode({'t': 'text', 'transferId': transferId, 'text': trimmed}),
    );

    try {
      final result = await ack.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw TimeoutException('Получатель не подтвердил текст'),
      );
      if (!result.ok) {
        throw StateError(result.reason ?? 'Текст не принят');
      }
    } finally {
      if (_pendingTextAck == ack) _pendingTextAck = null;
    }
  }

  Future<void> sendPaired(String deviceName) async {
    await link.sendText(
      jsonEncode({
        't': 'paired',
        'deviceName': deviceName.isEmpty ? 'Устройство' : deviceName,
      }),
    );
  }

  Future<void> cancel([String reason = 'Передача отменена']) async {
    _aborted = true;
    final id = _activeTransferId;
    if (id != null) {
      try {
        await link.sendText(
          jsonEncode({'t': 'cancel', 'transferId': id, 'reason': reason}),
        );
      } catch (_) {}
    }
    _pendingAccept?.completeError(StateError(reason));
    _pendingAccept = null;
    _pendingDone?.complete();
    _pendingDone = null;
    await _cleanupIncoming();
    callbacks.onFinished?.call(_incomingOutcomes, true);
  }

  void _handleControlText(String raw) {
    if (_disposed) return;
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    switch (decoded['t']) {
      case 'offer':
        final rawManifest = decoded['manifest'];
        if (rawManifest is! Map<String, dynamic>) return;
        try {
          final manifest = TransferManifest.validate(rawManifest);
          _pendingOffer = manifest;
          callbacks.onOffer?.call(manifest);
        } catch (e) {
          callbacks.onError?.call(e);
        }
      case 'accept':
        final idsRaw = decoded['ids'];
        if (idsRaw is List && _pendingAccept != null && !_pendingAccept!.isCompleted) {
          _pendingAccept!.complete(idsRaw.whereType<int>().toList());
        }
      case 'reject':
        final reason = decoded['reason'] as String? ?? 'Получатель отклонил файлы';
        if (_pendingAccept != null && !_pendingAccept!.isCompleted) {
          _pendingAccept!.completeError(StateError(reason));
        }
      case 'file-end':
        final transferId = decoded['transferId'] as String? ?? '';
        final id = decoded['id'];
        final size = decoded['size'];
        final expectedSha = (decoded['sha256'] as String? ?? '').toLowerCase();
        if (id is int && size is int) {
          _writeQueue = _writeQueue.then(
            (_) => _finalizeIncomingFile(transferId, id, size, expectedSha),
          );
        }
      case 'file-result':
        break;
      case 'done':
        if (_pendingDone != null && !_pendingDone!.isCompleted) {
          _pendingDone!.complete();
        }
      case 'cancel':
        final reason = decoded['reason'] as String? ?? 'Передача отменена';
        _aborted = true;
        if (_pendingAccept != null && !_pendingAccept!.isCompleted) {
          _pendingAccept!.completeError(StateError(reason));
        }
        if (_pendingDone != null && !_pendingDone!.isCompleted) {
          _pendingDone!.complete();
        }
        _cleanupIncoming();
        callbacks.onError?.call(StateError(reason));
      case 'text':
        final transferId = decoded['transferId'] as String? ?? '';
        final text = decoded['text'] as String? ?? '';
        if (text.isNotEmpty) {
          callbacks.onText?.call(text);
          link.sendText(
            jsonEncode({'t': 'text-ack', 'transferId': transferId, 'ok': true}),
          );
        }
      case 'text-ack':
        final ok = decoded['ok'] as bool? ?? false;
        final reason = decoded['reason'] as String?;
        if (_pendingTextAck != null && !_pendingTextAck!.isCompleted) {
          _pendingTextAck!.complete((ok: ok, reason: reason));
        }
      case 'paired':
        final dev = decoded['deviceName'] as String? ?? 'Устройство';
        callbacks.onPaired?.call(dev);
      case 'ping':
        link.sendText(jsonEncode({'t': 'pong', 'at': decoded['at']}));
    }
  }

  void _handleBinaryFrame(Uint8List raw) {
    if (_disposed || _aborted) return;
    _writeQueue = _writeQueue.then((_) async {
      if (_disposed || _aborted) return;
      final frame = decodeDataFrame(raw);
      final state = _incomingEntries[frame.fileId];
      if (state == null || state.closed) return;
      if (frame.seq != state.seq) {
        throw StateError('Нарушен порядок блоков для ${state.entry.name}');
      }
      state.fileSink ??= await callbacks.createIncomingSink(state.entry);
      await state.fileSink!.write(frame.payload);
      state.hashSink.add(frame.payload);
      state.bytes += frame.payload.length;
      state.seq++;

      final tid = _incomingManifest?.transferId ?? 'rx';
      callbacks.onProgress?.call(
        TransferProgress(
          transferId: '${tid}_${state.entry.id}',
          fileName: state.entry.name,
          bytesTransferred: state.bytes,
          totalBytes: state.entry.size,
          speedBytesPerSec: 0,
          status: TransferStatus.transferring,
          direction: TransferDirection.received,
          peerLabel: peerName,
        ),
      );
    }).catchError((Object e) {
      callbacks.onError?.call(e);
    });
  }

  Future<void> _finalizeIncomingFile(
    String transferId,
    int fileId,
    int expectedSize,
    String expectedSha256,
  ) async {
    final state = _incomingEntries[fileId];
    final manifest = _incomingManifest;
    if (state == null || manifest == null || state.closed) return;
    state.closed = true;

    try {
      state.fileSink ??= await callbacks.createIncomingSink(state.entry);
      state.hashSink.close();
      final actualSha = state.digestSink.digest?.toString() ?? '';

      if (state.bytes != expectedSize || actualSha != expectedSha256) {
        await state.fileSink!.abort();
        throw StateError('Контрольная сумма SHA-256 не совпала для ${state.entry.name}');
      }

      final savedLocation = await state.fileSink!.close();
      callbacks.onProgress?.call(
        TransferProgress(
          transferId: '${transferId}_${state.entry.id}',
          fileName: state.entry.name,
          bytesTransferred: state.bytes,
          totalBytes: state.entry.size,
          speedBytesPerSec: 0,
          status: TransferStatus.completed,
          direction: TransferDirection.received,
          peerLabel: peerName,
          savedPath: savedLocation,
        ),
      );

      _incomingOutcomes.add(
        TransferHistoryEntry(
          id: '${transferId}_${state.entry.id}',
          fileName: state.entry.name,
          sizeBytes: state.bytes,
          direction: TransferDirection.received,
          peerName: peerName,
          timestamp: DateTime.now(),
          success: true,
          localPath: savedLocation,
        ),
      );

      await link.sendText(
        jsonEncode({
          't': 'file-result',
          'transferId': transferId,
          'id': fileId,
          'ok': true,
        }),
      );
    } catch (e) {
      await state.fileSink?.abort();
      _incomingOutcomes.add(
        TransferHistoryEntry(
          id: '${transferId}_${state.entry.id}',
          fileName: state.entry.name,
          sizeBytes: state.bytes,
          direction: TransferDirection.received,
          peerName: peerName,
          timestamp: DateTime.now(),
          success: false,
          errorMessage: e.toString(),
        ),
      );
      await link.sendText(
        jsonEncode({
          't': 'file-result',
          'transferId': transferId,
          'id': fileId,
          'ok': false,
          'reason': e.toString(),
        }),
      );
    }

    if (_incomingOutcomes.length == _incomingEntries.length) {
      final failedCount = _incomingOutcomes.where((o) => !o.success).length;
      await link.sendText(
        jsonEncode({
          't': 'done',
          'transferId': transferId,
          'received': _incomingOutcomes.length - failedCount,
          'failed': failedCount,
        }),
      );
      final results = List<TransferHistoryEntry>.from(_incomingOutcomes);
      _incomingEntries.clear();
      _incomingManifest = null;
      _activeTransferId = null;
      callbacks.onFinished?.call(results, false);
    }
  }

  Future<void> _cleanupIncoming() async {
    for (final entry in _incomingEntries.values) {
      if (!entry.closed) {
        entry.closed = true;
        await entry.fileSink?.abort();
      }
    }
    _incomingEntries.clear();
    _incomingManifest = null;
    _activeTransferId = null;
  }

  void dispose([String? reason]) {
    if (_disposed) return;
    _disposed = true;
    _aborted = true;
    if (_pendingAccept != null && !_pendingAccept!.isCompleted) {
      _pendingAccept!.completeError(StateError(reason ?? 'Соединение закрыто'));
    }
    if (_pendingDone != null && !_pendingDone!.isCompleted) {
      _pendingDone!.complete();
    }
    if (_pendingTextAck != null && !_pendingTextAck!.isCompleted) {
      _pendingTextAck!.completeError(StateError(reason ?? 'Соединение закрыто'));
    }
    _cleanupIncoming();
  }
}
