import 'dart:io';

/// Represents a local IPv4 interface address suitable for LAN discovery.
class NetworkInterfaceAddress {
  const NetworkInterfaceAddress({
    required this.interfaceName,
    required this.ipAddress,
    required this.score,
  });

  final String interfaceName;
  final String ipAddress;
  final int score;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkInterfaceAddress &&
          interfaceName == other.interfaceName &&
          ipAddress == other.ipAddress;

  @override
  int get hashCode => Object.hash(interfaceName, ipAddress);
}

/// Discovers active local IPv4 addresses and friendly device metadata.
class IpResolver {
  static Future<List<NetworkInterfaceAddress>> getLocalIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );

    final candidates = <NetworkInterfaceAddress>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback || addr.isLinkLocal) continue;
        final ip = addr.address;
        if (ip.startsWith('169.254.')) continue;
        candidates.add(
          NetworkInterfaceAddress(
            interfaceName: iface.name,
            ipAddress: ip,
            score: _scoreInterface(iface.name, ip),
          ),
        );
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  static int _scoreInterface(String name, String ip) {
    var score = 0;
    final lower = name.toLowerCase();

    // Prioritize standard Wi-Fi / LAN interface names across OSes.
    if (lower.startsWith('en') ||
        lower.startsWith('wlan') ||
        lower.contains('wi-fi') ||
        lower.contains('wifi')) {
      score += 50;
    } else if (lower.startsWith('eth') || lower.contains('ethernet')) {
      score += 40;
    } else if (lower.startsWith('ap') || lower.contains('hotspot')) {
      score += 35;
    }

    // Penalize common virtual/tunnel adapters so real LAN IPs come first.
    if (lower.contains('utun') ||
        lower.contains('tun') ||
        lower.contains('tap') ||
        lower.contains('vbox') ||
        lower.contains('vmware') ||
        lower.contains('docker') ||
        lower.contains('veth') ||
        lower.contains('bridge')) {
      score -= 60;
    }

    // Prefer RFC 1918 private LAN ranges.
    if (ip.startsWith('192.168.')) {
      score += 30;
    } else if (ip.startsWith('10.')) {
      score += 20;
    } else if (ip.startsWith('172.')) {
      score += 15;
    }

    return score;
  }

  static String getPlatformLabel() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return Platform.operatingSystem;
  }

  static String getDeviceDisplayName() {
    final host = Platform.localHostname.trim();
    final os = getPlatformLabel();
    if (host.isEmpty || host.toLowerCase() == 'localhost') {
      return 'Луч ($os)';
    }
    return '$host ($os)';
  }
}
