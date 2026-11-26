import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Pure-Dart QR code decoder for image files (used on Desktop and from gallery).
class QrImageDecoder {
  static Future<String?> decodeFile(File file) async {
    final bytes = await file.readAsBytes();
    return decodeBytes(bytes);
  }

  static String? decodeBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final width = decoded.width;
    final height = decoded.height;
    final argbPixels = Int32List(width * height);

    var index = 0;
    for (final pixel in decoded) {
      final a = pixel.a.toInt().clamp(0, 255);
      final r = pixel.r.toInt().clamp(0, 255);
      final g = pixel.g.toInt().clamp(0, 255);
      final b = pixel.b.toInt().clamp(0, 255);
      argbPixels[index++] = (a << 24) | (r << 16) | (g << 8) | b;
    }

    final source = RGBLuminanceSource(width, height, argbPixels);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    final reader = QRCodeReader();

    try {
      return reader.decode(bitmap).text;
    } catch (_) {
      // Retry with GlobalHistogramBinarizer for low-contrast photos/screenshots.
      try {
        final fallbackBitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
        return reader.decode(fallbackBitmap).text;
      } catch (_) {
        return null;
      }
    }
  }
}
