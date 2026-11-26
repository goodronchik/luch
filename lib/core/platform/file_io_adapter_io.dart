import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../protocol/transfer_models.dart';
import '../storage/download_path_service.dart';
import '../webrtc/transfer_protocol.dart';
import 'file_io_adapter.dart';

class _DiskOutgoingFileSource implements OutgoingFileSource {
  _DiskOutgoingFileSource({
    required this.id,
    required this.name,
    required this.size,
    required this.filePath,
    this.mimeType,
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final int size;
  final String filePath;
  @override
  final String? mimeType;
  @override
  String? get relativePath => null;

  @override
  String? get displayPath => filePath;

  @override
  Future<Uint8List> readRange(int start, int end) async {
    final raf = await File(filePath).open(mode: FileMode.read);
    try {
      await raf.setPosition(start);
      final count = end - start;
      return await raf.read(count);
    } finally {
      await raf.close();
    }
  }
}

class _DiskIncomingFileSink implements IncomingFileSink {
  _DiskIncomingFileSink({
    required this.baseDir,
    required this.entry,
  });

  final Directory baseDir;
  final ManifestFileEntry entry;

  File? _targetFile;
  File? _partFile;
  IOSink? _sink;
  bool _closed = false;

  Future<void> _ensureOpen() async {
    if (_sink != null) return;
    var destDir = baseDir;
    final rel = entry.relativePath;
    if (rel != null && rel.isNotEmpty) {
      final segments = rel.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.length > 1) {
        for (var i = 0; i < segments.length - 1; i++) {
          destDir = Directory(p.join(destDir.path, sanitizeFileName(segments[i])));
        }
      }
    }
    _targetFile =
        await DownloadPathService.resolveUniqueTargetFile(destDir, entry.name);
    _partFile = File('${_targetFile!.path}.part');
    _sink = _partFile!.openWrite();
  }

  @override
  Future<void> write(Uint8List chunk) async {
    if (_closed) throw StateError('Файл уже закрыт');
    await _ensureOpen();
    _sink!.add(chunk);
  }

  @override
  Future<String> close() async {
    if (_closed) return _targetFile?.path ?? '';
    await _ensureOpen();
    await _sink!.flush();
    await _sink!.close();
    _sink = null;
    _closed = true;
    await _partFile!.rename(_targetFile!.path);
    return _targetFile!.path;
  }

  @override
  Future<void> abort() async {
    _closed = true;
    try {
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    if (_partFile != null && await _partFile!.exists()) {
      try {
        await _partFile!.delete();
      } catch (_) {}
    }
  }
}

Future<String> resolveDefaultSaveDirectoryPath() async {
  try {
    final dir = await DownloadPathService.resolveLuchDirectory();
    return dir.path;
  } catch (_) {
    return Directory.systemTemp.path;
  }
}

Future<IncomingFileSink> createIncomingSink(
  ManifestFileEntry entry, {
  String? customDirectoryPath,
}) async {
  final dir = (customDirectoryPath != null && customDirectoryPath.isNotEmpty)
      ? Directory(customDirectoryPath)
      : await DownloadPathService.resolveLuchDirectory();
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return _DiskIncomingFileSink(baseDir: dir, entry: entry);
}

Future<List<OutgoingFileSource>> sourcesFromPlatformFiles(
  List<PlatformFile> files,
) async {
  final out = <OutgoingFileSource>[];
  for (final pf in files) {
    final path = pf.path;
    if (path == null) continue;
    final f = File(path);
    if (!await f.exists()) continue;
    final size = await f.length();
    out.add(
      _DiskOutgoingFileSource(
        id: 'io_${DateTime.now().microsecondsSinceEpoch}_${out.length}',
        name: pf.name,
        size: size,
        filePath: path,
        mimeType: guessMimeType(pf.name),
      ),
    );
  }
  return out;
}

Future<List<OutgoingFileSource>> sourcesFromDropFiles(
  List<dynamic> dropFiles,
) async {
  final out = <OutgoingFileSource>[];
  for (final item in dropFiles) {
    final dynamic dyn = item;
    final String? path = dyn.path as String?;
    if (path == null) continue;
    final f = File(path);
    if (!await f.exists()) continue;
    final size = await f.length();
    final name = p.basename(path);
    out.add(
      _DiskOutgoingFileSource(
        id: 'drop_${DateTime.now().microsecondsSinceEpoch}_${out.length}',
        name: name,
        size: size,
        filePath: path,
        mimeType: guessMimeType(name),
      ),
    );
  }
  return out;
}
