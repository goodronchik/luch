import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/protocol/transfer_models.dart';
import '../../state/luch_controller.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.controller});

  final LuchController controller;

  Future<void> _openSaveFolder(BuildContext context) async {
    final path = controller.saveDirectory?.path;
    if (path == null) return;
    final uri = Uri.directory(path);
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Файлы сохраняются в: $path')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = controller.history;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_open_rounded, color: AppTheme.amber),
            title: const Text('Папка принятых файлов'),
            subtitle: Text(
              controller.saveDirectoryPath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                ? OutlinedButton(
                    onPressed: () => _openSaveFolder(context),
                    child: const Text('Открыть'),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 48, color: Colors.white30),
                SizedBox(height: 12),
                Text(
                  'История передач пока пуста',
                  style: TextStyle(color: Colors.white60),
                ),
              ],
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: AppTheme.border),
                  _HistoryTile(entry: items[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final TransferHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final isSent = entry.direction == TransferDirection.sent;
    final color = entry.success ? AppTheme.success : AppTheme.danger;
    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
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
      trailing: Text(
        timeStr,
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
    );
  }
}
