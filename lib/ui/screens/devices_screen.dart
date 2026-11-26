import 'package:material_ui/material_ui.dart';

import '../../core/platform/platform_info.dart';
import '../../core/protocol/transfer_models.dart';
import '../../core/storage/paired_devices_store.dart';
import '../../state/luch_controller.dart';
import '../theme/app_theme.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({
    super.key,
    required this.controller,
    required this.onJumpToSend,
  });

  final LuchController controller;
  final VoidCallback onJumpToSend;

  Future<void> _openHistoryEntry(
    BuildContext context,
    TransferHistoryEntry entry,
  ) async {
    final err = await controller.openReceivedFile(entry.localPath);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final devices = c.devices;
    final history = c.history;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.devices_other_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Сопряжённые устройства',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            c.presenceStatus == 'online'
                                ? 'Присутствие онлайн — автоприём подключений'
                                : (devices.isEmpty
                                    ? 'После первой передачи устройства сохранятся здесь'
                                    : 'Подключение к каналу присутствия...'),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onPressed: () async {
                        await c.startWebRtcPairOnly();
                        onJumpToSend();
                      },
                      icon: const Icon(Icons.add_link_rounded, size: 18),
                      label: const Text('Сопрячь'),
                    ),
                  ],
                ),
                if (devices.isEmpty) ...[
                  const SizedBox(height: 20),
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.phonelink_setup_rounded,
                          size: 44,
                          color: Theme.of(context).hintColor,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Сопряжённых устройств пока нет',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Отправьте файлы или нажмите «Сопрячь», чтобы соединяться в одно касание без QR.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  for (var i = 0; i < devices.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 22,
                        color: isDark ? AppTheme.border : AppTheme.lightBorder,
                      ),
                    _PairedDeviceRow(
                      device: devices[i],
                      lastSeenText: _formatTime(devices[i].lastSeenMs),
                      onConnect: () {
                        c.connectToPairedDevice(devices[i]);
                        onJumpToSend();
                      },
                      onForget: () => c.forgetDevice(devices[i].id),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading:
                const Icon(Icons.folder_open_rounded, color: AppTheme.amber),
            title: const Text('Папка сохранения'),
            subtitle: Text(
              c.saveDirectoryDisplay,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PlatformInfo.isDesktopNative
                ? OutlinedButton(
                    onPressed: () async {
                      final ok =
                          await PlatformInfo.openFolder(c.saveDirectoryDisplay);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Папка: ${c.saveDirectoryDisplay}'),
                          ),
                        );
                      }
                    },
                    child: const Text('Открыть'),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 18),
        Text('История передач', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (history.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Передач пока не было',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: isDark ? AppTheme.border : AppTheme.lightBorder,
                    ),
                  _HistoryRow(
                    entry: history[i],
                    onTapOpen: () => _openHistoryEntry(context, history[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _formatTime(int ms) {
    if (ms <= 0) return 'недавно';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} $hh:$mm';
  }
}

class _PairedDeviceRow extends StatelessWidget {
  const _PairedDeviceRow({
    required this.device,
    required this.lastSeenText,
    required this.onConnect,
    required this.onForget,
  });

  final PairedDevice device;
  final String lastSeenText;
  final VoidCallback onConnect;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primary.withValues(alpha: 0.14),
              child: Icon(Icons.devices_rounded, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Последний контакт: $lastSeenText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Забыть устройство',
              onPressed: onForget,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: onConnect,
          icon: const Icon(Icons.link_rounded, size: 18),
          label: const Text('Подключиться'),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.onTapOpen,
  });

  final TransferHistoryEntry entry;
  final VoidCallback onTapOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSent = entry.direction == TransferDirection.sent;
    final canOpen = !isSent &&
        entry.success &&
        entry.localPath != null &&
        entry.localPath!.isNotEmpty;
    final color = entry.success ? AppTheme.success : AppTheme.danger;
    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: canOpen ? onTapOpen : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(
                isSent ? Icons.north_east_rounded : Icons.south_west_rounded,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: canOpen ? cs.primary : null,
                      decoration: canOpen ? TextDecoration.underline : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${isSent ? "Отправлено" : "Принято"} • ${formatBytes(entry.sizeBytes)} • ${entry.peerName}'
                    '${entry.errorMessage != null ? "\n${entry.errorMessage}" : ""}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(timeStr, style: Theme.of(context).textTheme.bodySmall),
                if (canOpen) ...[
                  const SizedBox(height: 2),
                  Icon(Icons.open_in_new_rounded, size: 15, color: cs.primary),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
