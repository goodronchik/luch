import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../protocol/transfer_models.dart';

/// Resolves platform-appropriate save folders and avoids filename collisions.
class DownloadPathService {
  static Future<Directory> resolveLuchDirectory() async {
    Directory? baseDir;

    if (Platform.isAndroid) {
      // Try public Downloads/Luch first when accessible; fall back gracefully.
      final publicDownloads = Directory('/storage/emulated/0/Download');
      if (await publicDownloads.exists()) {
        final candidate = Directory(p.join(publicDownloads.path, 'Luch'));
        try {
          await candidate.create(recursive: true);
          return candidate;
        } catch (_) {
          // Fall back to app-scoped external/documents directory on scoped storage.
        }
      }
      baseDir = await getDownloadsDirectory() ??
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      // Exposed in the iOS Files app when UIFileSharingEnabled is true.
      baseDir = await getApplicationDocumentsDirectory();
    } else {
      baseDir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }

    final luchDir = Directory(p.join(baseDir.path, 'Luch'));
    if (!await luchDir.exists()) {
      await luchDir.create(recursive: true);
    }
    return luchDir;
  }

  /// Returns a non-colliding file path in [directory] for [rawFileName].
  static Future<File> resolveUniqueTargetFile(
    Directory directory,
    String rawFileName,
  ) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final safeName = sanitizeFileName(rawFileName);
    final baseName = p.basenameWithoutExtension(safeName);
    final extension = p.extension(safeName);

    var candidate = File(p.join(directory.path, safeName));
    var counter = 1;
    while (await candidate.exists()) {
      candidate = File(
        p.join(directory.path, '$baseName ($counter)$extension'),
      );
      counter++;
    }
    return candidate;
  }
}
