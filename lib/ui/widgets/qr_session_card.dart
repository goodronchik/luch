import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network/ip_resolver.dart';
import '../theme/app_theme.dart';

class QrSessionCard extends StatelessWidget {
  const QrSessionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.qrUrl,
    required this.interfaces,
    required this.selectedInterface,
    required this.onSelectInterface,
    required this.onStop,
  });

  final String title;
  final String subtitle;
  final String qrUrl;
  final List<NetworkInterfaceAddress> interfaces;
  final NetworkInterfaceAddress? selectedInterface;
  final ValueChanged<NetworkInterfaceAddress> onSelectInterface;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2_rounded, color: AppTheme.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_circle_outlined,
                      color: AppTheme.danger),
                  label: const Text(
                    'Остановить',
                    style: TextStyle(color: AppTheme.danger),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: qrUrl,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      qrUrl,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Скопировать ссылку',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: qrUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ссылка скопирована в буфер обмена'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                ],
              ),
            ),
            if (interfaces.length > 1) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Сетевой адрес:',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<NetworkInterfaceAddress>(
                      initialValue: selectedInterface,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: interfaces
                          .map(
                            (iface) => DropdownMenuItem(
                              value: iface,
                              child: Text(
                                '${iface.ipAddress} (${iface.interfaceName})',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) onSelectInterface(val);
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Отсканируйте QR через приложение «Луч» или откройте в браузере на устройстве в той же сети Wi-Fi.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
