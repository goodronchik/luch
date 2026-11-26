import 'package:material_ui/material_ui.dart';

import '../../core/platform/platform_info.dart';
import '../../core/protocol/transfer_models.dart';
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
                  children: [
                    Icon(Icons.devices_other_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Сопряжённые устройства',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            c.presenceStatus == 'online'
                                ? 'Присутствие онлайн — подключение в одно касание'
                                : (devices.isEmpty
                                    ? 'После первой передачи устройства сохранятся здесь'
                                    : 'Ожидание подключения к каналу присутствия'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await c.startWebRtcPairOnly();
                        onJumpToSend();
                      },
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('Сопрячь'),
                    ),
                  ],
                ),
                if (devices.isEmpty) ...[
                  const SizedBox(height: 18),
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
                          'Отправьте файлы или нажмите «Сопрячь», чтобы соединяться без QR в следующий раз.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  for (var i = 0; i < devices.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        color: isDark ? AppTheme.border : AppTheme.lightBorder,
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: cs.primary.withValues(alpha: 0.14),
                        child: Icon(Icons.devices_rounded, color: cs.primary),
                      ),
                      title: Text(
                        devices[i].name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Последний контакт: ${_formatTime(devices[i].lastSeenMs)}',
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              c.connectToPairedDevice(devices[i]);
                              onJumpToSend();
                            },
                            child: const Text('Подключиться'),
                          ),
                          IconButton(
                            tooltip: 'Забыть устройство',
                            onPressed: () => c.forgetDevice(devices[i].id),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_open_rounded, color: AppTheme.amber),
            title: const Text('Папка сохранения'),
            subtitle: Text(c.saveDirectoryDisplay),
            trailing: PlatformInfo.isDesktopNative
                ? OutlinedButton(
                    onPressed: () async {
                      final ok =
                          await PlatformInfo.openFolder(c.saveDirectoryDisplay);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Папка: ${c.saveDirectoryDisplay}')),
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
                  _HistoryRow(entry: history[i]),
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

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final TransferHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final isSent = entry.direction == TransferDirection.sent;
    final color = entry.success ? AppTheme.success : AppTheme.danger;
    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.14),
        child: Icon(
          isSent ? Icons.north_east_rounded : Icons.south_west_rounded,
          color: color,
        ),
      ),
      title: Text(
        entry.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${isSent ? "Отправлено" : "Принято"} • ${formatBytes(entry.sizeBytes)} • ${entry.peerName}'
        '${entry.errorMessage != null ? "\n${entry.errorMessage}" : ""}',
      ),
      trailing: Text(timeStr, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
