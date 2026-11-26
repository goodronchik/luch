import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/protocol/transfer_models.dart';
import '../../state/luch_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/qr_session_card.dart';
import '../widgets/transfer_progress_tile.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.controller});

  final LuchController controller;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  bool _isDragging = false;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _pickFiles() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Выберите файлы для отправки',
    );
    if (picked.isEmpty) return;
    final paths =
        picked.map((f) => f.path).whereType<String>().toList(growable: false);
    if (paths.isNotEmpty) {
      await widget.controller.addLocalPaths(paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final files = c.queuedSendFiles;
    final totalSize = files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
    final sendProgress = c.transfers
        .where((t) => t.direction == TransferDirection.sent)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropTarget(
          enable: _isDesktop,
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: (details) async {
            setState(() => _isDragging = false);
            final paths = details.files.map((x) => x.path).toList();
            await c.addLocalPaths(paths);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _isDragging
                  ? AppTheme.accent.withValues(alpha: 0.12)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _isDragging ? AppTheme.accent : AppTheme.border,
                width: _isDragging ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.upload_file_rounded,
                  size: 42,
                  color: _isDragging ? AppTheme.accent : AppTheme.amber,
                ),
                const SizedBox(height: 10),
                Text(
                  _isDesktop
                      ? 'Перетащите файлы сюда или выберите на диске'
                      : 'Выберите файлы для отправки по QR-коду',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Файлы передаются напрямую в локальной сети без сжатия и без интернета.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.white60),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickFiles,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Выбрать файлы'),
                    ),
                    if (files.isNotEmpty && !c.isSending)
                      FilledButton.tonalIcon(
                        onPressed: c.startSendSession,
                        icon: const Icon(Icons.qr_code_rounded),
                        label: const Text('Создать QR-код'),
                      ),
                    if (files.isNotEmpty)
                      TextButton.icon(
                        onPressed: c.clearQueuedFiles,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Очистить'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (c.statusError != null) ...[
          const SizedBox(height: 14),
          _ErrorBanner(
            message: c.statusError!,
            onDismiss: c.clearError,
          ),
        ],
        if (c.isSending && c.activeQrUrl != null) ...[
          const SizedBox(height: 16),
          QrSessionCard(
            title: 'Раздача активна',
            subtitle:
                'Файлов: ${files.length} • Общий объём: ${formatBytes(totalSize)}',
            qrUrl: c.activeQrUrl!,
            interfaces: c.interfaces,
            selectedInterface: c.selectedInterface,
            onSelectInterface: c.selectInterface,
            onStop: c.stopServer,
          ),
        ],
        if (files.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Выбрано файлов: ${files.length} (${formatBytes(totalSize)})',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Colors.white70),
              ),
              if (!c.isSending)
                TextButton.icon(
                  onPressed: c.startSendSession,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Показать QR'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < files.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: AppTheme.border),
                  ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined,
                        color: AppTheme.accent),
                    title: Text(
                      files[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(formatBytes(files[i].sizeBytes)),
                    trailing: IconButton(
                      tooltip: 'Удалить',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => c.removeQueuedFile(files[i].id),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (sendProgress.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Активные и недавние отправки',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Colors.white70),
              ),
              TextButton(
                onPressed: c.clearCompletedTransfers,
                child: const Text('Скрыть завершённые'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in sendProgress) TransferProgressTile(progress: item),
        ],
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
