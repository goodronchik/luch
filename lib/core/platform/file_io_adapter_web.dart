import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

import '../webrtc/transfer_protocol.dart';
import 'file_io_adapter.dart';

class _WebOutgoingFileSource implements OutgoingFileSource {
  _WebOutgoingFileSource({
    required this.id,
    required this.name,
    required this.size,
    required this.bytes,
    this.mimeType,
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final int size;
  final Uint8List bytes;
  @override
  final String? mimeType;
  @override
  String? get relativePath => null;
  @override
  String? get displayPath => name;

  @override
  Future<Uint8List> readRange(int start, int end) async {
    return Uint8List.sublistView(bytes, start, end);
  }
}

class _WebIncomingFileSink implements IncomingFileSink {
  _WebIncomingFileSink({required this.entry});

  final ManifestFileEntry entry;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  bool _aborted = false;

  @override
  Future<void> write(Uint8List chunk) async {
    if (_aborted) throw StateError('Приём отменён');
    _builder.add(chunk);
  }

  @override
  Future<String> close() async {
    if (_aborted) throw StateError('Приём отменён');
    final bytes = _builder.takeBytes();
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: entry.type),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = entry.name
      ..rel = 'noopener';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    Future<void>.delayed(
      const Duration(seconds: 60),
      () => web.URL.revokeObjectURL(url),
    );
    return 'Загружено в браузере';
  }

  @override
  Future<void> abort() async {
    _aborted = true;
    _builder.clear();
  }
}

Future<String> resolveDefaultSaveDirectoryPath() async => 'Загрузки браузера';

Future<IncomingFileSink> createIncomingSink(
  ManifestFileEntry entry, {
  String? customDirectoryPath,
}) async {
  return _WebIncomingFileSink(entry: entry);
}

Future<List<OutgoingFileSource>> sourcesFromPlatformFiles(
  List<PlatformFile> files,
) async {
  final out = <OutgoingFileSource>[];
  for (final pf in files) {
    final data = await pf.readAsBytes();
    out.add(
      _WebOutgoingFileSource(
        id: 'web_${DateTime.now().microsecondsSinceEpoch}_${out.length}',
        name: pf.name,
        size: data.length,
        bytes: data,
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
    final Uint8List bytes = await (dyn.readAsBytes() as Future<Uint8List>);
    final String name = (dyn.name as String?) ?? 'file';
    out.add(
      _WebOutgoingFileSource(
        id: 'wdrop_${DateTime.now().microsecondsSinceEpoch}_${out.length}',
        name: name,
        size: bytes.length,
        bytes: bytes,
        mimeType: guessMimeType(name),
      ),
    );
  }
  return out;
}
