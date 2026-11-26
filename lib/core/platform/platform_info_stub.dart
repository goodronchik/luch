abstract final class PlatformInfo {
  static String platformLabel() => 'Unknown';
  static String defaultDeviceName() => 'Луч';
  static bool get isWeb => false;
  static bool get isDesktopNative => false;
  static bool get supportsLiveCamera => false;
  static bool get supportsLocalLanServer => false;
  static String? consumeInitialPairSecret() => null;
  static Future<bool> openFolder(String path) async => false;
  static Future<String?> openFile(String path) async => 'Не поддерживается';
}
