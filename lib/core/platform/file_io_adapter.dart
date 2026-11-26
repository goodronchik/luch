import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../webrtc/transfer_protocol.dart';
import 'file_io_adapter_stub.dart'
    if (dart.library.io) 'file_io_adapter_io.dart'
    if (dart.library.js_interop) 'file_io_adapter_web.dart' as impl;

abstract class OutgoingFileSource {
  String get id;
  String get name;
  int get size;
  String? get mimeType;
  String? get relativePath;
  String? get displayPath;

  Future<Uint8List> readRange(int start, int end);
}

abstract class IncomingFileSink {
  Future<void> write(Uint8List chunk);
  Future<String> close();
  Future<void> abort();
}

abstract final class PlatformFileStorage {
  static Future<String> resolveDefaultSaveDirectoryPath() =>
      impl.resolveDefaultSaveDirectoryPath();

  static Future<IncomingFileSink> createIncomingSink(
    ManifestFileEntry entry, {
    String? customDirectoryPath,
  }) =>
      impl.createIncomingSink(entry, customDirectoryPath: customDirectoryPath);

  static Future<List<OutgoingFileSource>> sourcesFromPlatformFiles(
    List<PlatformFile> files,
  ) =>
      impl.sourcesFromPlatformFiles(files);

  static Future<List<OutgoingFileSource>> sourcesFromDropFiles(
    List<dynamic> dropFiles,
  ) =>
      impl.sourcesFromDropFiles(dropFiles);
}
