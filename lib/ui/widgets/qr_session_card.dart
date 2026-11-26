import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/platform/local_lan_bridge.dart';
import '../theme/app_theme.dart';

class QrSessionCard extends StatefulWidget {
  const QrSessionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.qrUrl,
    required this.onStop,
    this.manualCode,
    this.expiresAtMs,
    this.hintText,
    this.interfaces = const [],
    this.selectedInterface,
    this.onSelectInterface,
  });

  final String title;
  final String subtitle;
  final String qrUrl;
  final String? manualCode;
  final int? expiresAtMs;
  final String? hintText;
  final List<LanAddress> interfaces;
  final LanAddress? selectedInterface;
  final ValueChanged<LanAddress>? onSelectInterface;
  final VoidCallback onStop;

  @override
  State<QrSessionCard> createState() => _QrSessionCardState();
}

class _QrSessionCardState extends State<QrSessionCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.expiresAtMs != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String? _remainingLabel() {
    final exp = widget.expiresAtMs;
    if (exp == null) return null;
    final leftMs = exp - DateTime.now().millisecondsSinceEpoch;
    if (leftMs <= 0) return '0:00';
    final secs = leftMs ~/ 1000;
    final m = secs ~/ 60;
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final remaining = _remainingLabel();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        widget.subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (remaining != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      remaining,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.55),
                  width: 2,
                ),
              ),
              child: QrImageView(
                data: widget.qrUrl,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            if (widget.manualCode != null) ...[
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceAlt : AppTheme.lightSurfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? AppTheme.border : AppTheme.lightBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'КОД ВРУЧНУЮ',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            widget.manualCode!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Скопировать код',
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: widget.manualCode!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Код скопирован'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceAlt : AppTheme.lightSurfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      widget.qrUrl,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Скопировать ссылку',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.qrUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ссылка скопирована'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.link_rounded, size: 18),
                  ),
                ],
              ),
            ),
            if (widget.interfaces.length > 1 &&
                widget.onSelectInterface != null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<LanAddress>(
                initialValue: widget.selectedInterface,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Сетевой адрес Wi-Fi',
                  isDense: true,
                ),
                items: widget.interfaces
                    .map(
                      (iface) => DropdownMenuItem(
                        value: iface,
                        child: Text(
                          '${iface.ipAddress} (${iface.interfaceName})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) widget.onSelectInterface!(val);
                },
              ),
            ],
            if (widget.hintText != null) ...[
              const SizedBox(height: 10),
              Text(
                widget.hintText!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onStop,
                icon: const Icon(Icons.close_rounded, color: AppTheme.danger),
                label: const Text(
                  'Отменить',
                  style: TextStyle(color: AppTheme.danger),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
