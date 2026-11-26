import 'dart:typed_data';

/// Crockford Base32 encoding matching `@luch/core` (without I, L, O, U).
class CrockfordBase32 {
  static const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static final Map<String, int> _reverse = _buildReverse();

  static Map<String, int> _buildReverse() {
    final map = <String, int>{};
    for (var i = 0; i < alphabet.length; i++) {
      map[alphabet[i]] = i;
    }
    map['I'] = 1;
    map['L'] = 1;
    map['O'] = 0;
    map['U'] = 27;
    return Map.unmodifiable(map);
  }

  static String encode(Uint8List bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(alphabet[(buffer >> bits) & 31]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) {
      out.write(alphabet[(buffer << (5 - bits)) & 31]);
    }
    return out.toString();
  }

  static String normalize(String input) {
    return input.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
  }

  static Uint8List decode(String input) {
    final clean = normalize(input);
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (var i = 0; i < clean.length; i++) {
      final ch = clean[i];
      final value = _reverse[ch];
      if (value == null) {
        throw FormatException('Недопустимый символ Crockford Base32: $ch');
      }
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
      buffer &= (1 << bits) - 1;
    }
    return Uint8List.fromList(out);
  }
}
