import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../webrtc/pairing.dart';

enum AppThemePreference { system, dark, light }

class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.secret,
    required this.pairId,
    required this.lastSeenMs,
  });

  final String id;
  final String name;
  final String secret;
  final String pairId;
  final int lastSeenMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'secret': secret,
        'pairId': pairId,
        'lastSeen': lastSeenMs,
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    final secret = json['secret'] as String? ?? '';
    final pairId = json['pairId'] as String?;
    return PairedDevice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Устройство',
      secret: secret,
      pairId: (pairId != null && pairId.isNotEmpty)
          ? pairId
          : (LuchPairing.isValidSecret(secret)
              ? LuchPairing.pairIdFromSecret(secret)
              : ''),
      lastSeenMs: (json['lastSeen'] as num?)?.toInt() ?? 0,
    );
  }
}

class LuchSettings {
  const LuchSettings({
    required this.deviceId,
    required this.deviceName,
    required this.serverOrigin,
    required this.autoAccept,
    required this.theme,
    this.customSaveDirectory,
  });

  static const String defaultServerOrigin = 'https://main.lolkas.ru/luch';

  final String deviceId;
  final String deviceName;
  final String serverOrigin;
  final bool autoAccept;
  final AppThemePreference theme;
  final String? customSaveDirectory;

  LuchSettings copyWith({
    String? deviceName,
    String? serverOrigin,
    bool? autoAccept,
    AppThemePreference? theme,
    String? customSaveDirectory,
    bool clearCustomSaveDirectory = false,
  }) {
    return LuchSettings(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      serverOrigin: serverOrigin ?? this.serverOrigin,
      autoAccept: autoAccept ?? this.autoAccept,
      theme: theme ?? this.theme,
      customSaveDirectory: clearCustomSaveDirectory
          ? null
          : (customSaveDirectory ?? this.customSaveDirectory),
    );
  }
}

class LuchPreferencesStore {
  static const _keyDeviceId = 'luch.deviceId';
  static const _keyDeviceName = 'luch.deviceName';
  static const _keyServerOrigin = 'luch.serverOrigin';
  static const _keyAutoAccept = 'luch.autoAccept';
  static const _keyTheme = 'luch.theme';
  static const _keySaveDir = 'luch.saveDir';
  static const _keyDevices = 'luch.devices';

  Future<({LuchSettings settings, List<PairedDevice> devices})> load({
    required String defaultDeviceName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_keyDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString(_keyDeviceId, deviceId);
    }

    final deviceName = prefs.getString(_keyDeviceName) ?? defaultDeviceName;
    final serverOrigin =
        prefs.getString(_keyServerOrigin) ?? LuchSettings.defaultServerOrigin;
    final autoAccept = prefs.getBool(_keyAutoAccept) ?? true;
    final themeRaw = prefs.getString(_keyTheme) ?? 'dark';
    final theme = switch (themeRaw) {
      'light' => AppThemePreference.light,
      'system' => AppThemePreference.system,
      _ => AppThemePreference.dark,
    };
    final saveDir = prefs.getString(_keySaveDir);

    final devices = <PairedDevice>[];
    final devicesRaw = prefs.getString(_keyDevices);
    if (devicesRaw != null && devicesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(devicesRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final d = PairedDevice.fromJson(item);
              if (d.id.isNotEmpty && LuchPairing.isValidSecret(d.secret)) {
                devices.add(d);
              }
            }
          }
        }
      } catch (_) {}
    }
    devices.sort((a, b) => b.lastSeenMs.compareTo(a.lastSeenMs));

    return (
      settings: LuchSettings(
        deviceId: deviceId,
        deviceName: deviceName,
        serverOrigin: serverOrigin,
        autoAccept: autoAccept,
        theme: theme,
        customSaveDirectory: saveDir,
      ),
      devices: devices,
    );
  }

  Future<void> saveSettings(LuchSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceId, settings.deviceId);
    await prefs.setString(_keyDeviceName, settings.deviceName);
    await prefs.setString(_keyServerOrigin, settings.serverOrigin);
    await prefs.setBool(_keyAutoAccept, settings.autoAccept);
    await prefs.setString(_keyTheme, settings.theme.name);
    if (settings.customSaveDirectory != null &&
        settings.customSaveDirectory!.isNotEmpty) {
      await prefs.setString(_keySaveDir, settings.customSaveDirectory!);
    } else {
      await prefs.remove(_keySaveDir);
    }
  }

  Future<void> saveDevices(List<PairedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyDevices,
      jsonEncode(devices.map((d) => d.toJson()).toList()),
    );
  }
}
