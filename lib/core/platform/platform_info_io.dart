import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

abstract final class PlatformInfo {
  static const MethodChannel _deepLinkChannel =
      MethodChannel('app.luch.luch/deep_link');
  static String platformLabel() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return Platform.operatingSystem;
  }

  static String defaultDeviceName() {
    final host = Platform.localHostname.trim();
    final os = platformLabel();
    if (host.isEmpty || host.toLowerCase() == 'localhost') {
      return 'Луч ($os)';
    }
    return '$host ($os)';
  }

  static bool get isWeb => false;

  static bool get isDesktopNative =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static bool get supportsLiveCamera =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  static bool get supportsLocalLanServer => true;

  static String? consumeInitialPairSecret() => null;

  static Future<String?> consumeInitialDeepLink() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final link = await _deepLinkChannel.invokeMethod<String>('getInitialLink');
      return (link != null && link.trim().isNotEmpty) ? link.trim() : null;
    } catch (_) {
      return null;
    }
  }

  static void listenIncomingDeepLinks(void Function(String link) onLink) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _deepLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final raw = call.arguments;
        if (raw is String && raw.trim().isNotEmpty) {
          onLink(raw.trim());
        }
      }
    });
  }

  static Future<bool> openFolder(String path) async {
    if (!isDesktopNative) return false;
    return launchUrl(Uri.directory(path));
  }

  static Future<String?> openFile(String path) async {
    if (path.isEmpty) return 'Путь к файлу не найден';
    final file = File(path);
    if (!await file.exists()) {
      return 'Файл не найден на устройстве';
    }
    final result = await OpenFilex.open(path);
    if (result.type == ResultType.done) return null;
    return result.message.isNotEmpty
        ? result.message
        : 'Не удалось открыть файл';
  }
}
