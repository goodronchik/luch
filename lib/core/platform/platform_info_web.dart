import 'package:web/web.dart' as web;

import '../webrtc/pairing.dart';
import 'file_io_adapter_web.dart' as web_io;

abstract final class PlatformInfo {
  static String platformLabel() => 'Web';

  static String defaultDeviceName() {
    final ua = web.window.navigator.userAgent;
    if (ua.contains('Android')) return 'Браузер (Android)';
    if (ua.contains('iPhone') || ua.contains('iPad')) return 'Браузер (iOS)';
    if (ua.contains('Mac')) return 'Браузер (macOS)';
    if (ua.contains('Windows')) return 'Браузер (Windows)';
    if (ua.contains('Linux')) return 'Браузер (Linux)';
    return 'Браузер';
  }

  static bool get isWeb => true;
  static bool get isDesktopNative => false;
  static bool get supportsLiveCamera => true;
  static bool get supportsLocalLanServer => false;

  static String? consumeInitialPairSecret() {
    final href = web.window.location.href;
    final secret = LuchPairing.parsePairInput(href);
    if (secret != null) {
      final uri = Uri.tryParse(href);
      if (uri != null) {
        final clean = uri.replace(fragment: '').toString();
        web.window.history.replaceState(null, '', clean);
      }
    }
    return secret;
  }

  static Future<String?> consumeInitialDeepLink() async {
    return consumeInitialPairSecret();
  }

  static void listenIncomingDeepLinks(void Function(String link) onLink) {}

  static Future<bool> openFolder(String path) async => false;

  static Future<String?> openFile(String path) async {
    final ok = web_io.reopenCachedWebFile(path);
    if (ok) return null;
    return 'Файл уже сохранён в загрузки браузера';
  }
}
