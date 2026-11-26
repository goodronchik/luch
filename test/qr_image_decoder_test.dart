import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:luch/core/qr/qr_image_decoder.dart';
import 'package:zxing2/qrcode.dart';

void main() {
  test('QrImageDecoder decodes generated QR PNG bytes', () {
    const payload = 'http://192.168.1.42:54321/s/0123456789abcdef';
    final qr = Encoder.encode(payload, ErrorCorrectionLevel.m);
    final matrix = qr.matrix!;

    const scale = 6;
    const quiet = 4;
    final size = (matrix.width + quiet * 2) * scale;
    final canvas = img.Image(width: size, height: size);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        if (matrix.get(x, y) == 1) {
          final px = (x + quiet) * scale;
          final py = (y + quiet) * scale;
          img.fillRect(
            canvas,
            x1: px,
            y1: py,
            x2: px + scale - 1,
            y2: py + scale - 1,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }

    final pngBytes = Uint8List.fromList(img.encodePng(canvas));
    final decoded = QrImageDecoder.decodeBytes(pngBytes);
    expect(decoded, payload);
  });
}
