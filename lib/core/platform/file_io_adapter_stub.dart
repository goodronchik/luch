import 'package:file_picker/file_picker.dart';

import '../webrtc/transfer_protocol.dart';
import 'file_io_adapter.dart';

Future<String> resolveDefaultSaveDirectoryPath() async => 'Загрузки';

Future<IncomingFileSink> createIncomingSink(
  ManifestFileEntry entry, {
  String? customDirectoryPath,
}) {
  throw UnsupportedError('File storage is not supported on this platform');
}

Future<List<OutgoingFileSource>> sourcesFromPlatformFiles(
  List<PlatformFile> files,
) async =>
    const [];

Future<List<OutgoingFileSource>> sourcesFromDropFiles(
  List<dynamic> dropFiles,
) async =>
    const [];
