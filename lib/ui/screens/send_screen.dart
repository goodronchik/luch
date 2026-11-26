import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/file_io_adapter.dart';
import '../../core/platform/platform_info.dart';
import '../../core/protocol/transfer_models.dart';
import '../../core/webrtc/transfer_protocol.dart';
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
  final TextEditingController _textController = TextEditingController();
  bool _isDragging = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Выберите файлы для отправки',
    );
    if (picked.isEmpty) return;
    final sources = await PlatformFileStorage.sourcesFromPlatformFiles(picked);
    if (sources.isNotEmpty) {
      await widget.controller.addOutgoingSources(sources);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final files = c.queuedFiles;
    final totalSize = files.fold<int>(0, (sum, f) => sum + f.size);
    final sendProgress = c.transfers
        .where((t) => t.direction == TransferDirection.sent)
        .toList();

    if (_textController.text != c.draftText && c.draftText.isEmpty) {
      _textController.clear();
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (c.phase == WebRtcPhase.waiting && c.activePairUrl != null) ...[
          QrSessionCard(
            title: 'Покажите QR получателю',
            subtitle: c.sendMode == SendContentMode.text
                ? 'Текст (${c.draftText.trim().length} симв.)'
                : 'Файлов: ${files.length} • ${formatBytes(totalSize)}',
            qrUrl: c.activePairUrl!,
            manualCode: c.activeManualCode,
            expiresAtMs: c.expiresAtMs,
            hintText:
                'Наведите камеру второго устройства или откройте ссылку в браузере. Данные пойдут напрямую по WebRTC с проверкой SHA-256.',
            onStop: c.resetWebRtcSession,
          ),
          const SizedBox(height: 16),
        ] else if (c.phase == WebRtcPhase.connecting) ...[
          _ConnectionBanner(
            title: 'Устанавливаем прямое соединение...',
            subtitle: c.peerName ?? 'Обмен ключами и проверка канала',
            onCancel: c.resetWebRtcSession,
          ),
          const SizedBox(height: 16),
        ] else if (c.phase == WebRtcPhase.connected ||
            c.phase == WebRtcPhase.transferring ||
            c.phase == WebRtcPhase.done) ...[
          _ActiveSessionBanner(
            controller: c,
            onPickMoreFiles: () async {
              final picked = await FilePicker.pickFiles(
                dialogTitle: 'Отправить ещё файлы',
              );
              if (picked.isEmpty) return;
              final sources =
                  await PlatformFileStorage.sourcesFromPlatformFiles(picked);
              if (sources.isNotEmpty) {
                await c.sendFilesInActiveSession(sources);
              }
            },
          ),
          const SizedBox(height: 16),
        ],
        if (c.phase == WebRtcPhase.idle || c.phase == WebRtcPhase.error) ...[
          SegmentedButton<SendContentMode>(
            segments: const [
              ButtonSegment(
                value: SendContentMode.files,
                icon: Icon(Icons.insert_drive_file_outlined),
                label: Text('Файлы'),
              ),
              ButtonSegment(
                value: SendContentMode.text,
                icon: Icon(Icons.notes_rounded),
                label: Text('Текст'),
              ),
            ],
            selected: {c.sendMode},
            onSelectionChanged: (sel) => c.setSendMode(sel.first),
          ),
          const SizedBox(height: 16),
          if (c.sendMode == SendContentMode.files)
            DropTarget(
              enable: PlatformInfo.isDesktopNative || PlatformInfo.isWeb,
              onDragEntered: (_) => setState(() => _isDragging = true),
              onDragExited: (_) => setState(() => _isDragging = false),
              onDragDone: (details) async {
                setState(() => _isDragging = false);
                final sources =
                    await PlatformFileStorage.sourcesFromDropFiles(details.files);
                if (sources.isNotEmpty) {
                  await c.addOutgoingSources(sources);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _isDragging
                      ? cs.primary.withValues(alpha: 0.12)
                      : (isDark ? AppTheme.surface : AppTheme.lightSurface),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isDragging
                        ? cs.primary
                        : (isDark ? AppTheme.border : AppTheme.lightBorder),
                    width: _isDragging ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.cloud_upload_outlined,
                        size: 30,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      PlatformInfo.isDesktopNative || PlatformInfo.isWeb
                          ? 'Добавить файлы'
                          : 'Выберите файлы для отправки',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Файлы пойдут напрямую по WebRTC с проверкой SHA-256 — через любые сети или локально.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
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
                        if (files.isNotEmpty)
                          FilledButton.tonalIcon(
                            onPressed: c.startWebRtcSendFiles,
                            icon: const Icon(Icons.qr_code_rounded),
                            label: const Text('Показать QR (WebRTC)'),
                          ),
                        if (files.isNotEmpty && c.supportsLocalLan)
                          OutlinedButton.icon(
                            onPressed: c.isLanSending
                                ? c.stopLanServer
                                : c.startLanSend,
                            icon: const Icon(Icons.wifi_rounded),
                            label: Text(
                              c.isLanSending ? 'Стоп Wi-Fi' : 'Только по Wi-Fi',
                            ),
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
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Отправить текст или ссылку',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _textController,
                      maxLines: 6,
                      maxLength: luchMaxTextLength,
                      decoration: const InputDecoration(
                        hintText: 'Вставьте заметку, пароль, ссылку или текст...',
                      ),
                      onChanged: c.setDraftText,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: c.startWebRtcSendText,
                      icon: const Icon(Icons.qr_code_rounded),
                      label: const Text('Отправить текст по QR'),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (c.isLanSending && c.activeLanQrUrl != null) ...[
          const SizedBox(height: 16),
          QrSessionCard(
            title: 'Локальная Wi-Fi раздача (без интернета)',
            subtitle: 'Файлов: ${files.length} • ${formatBytes(totalSize)}',
            qrUrl: c.activeLanQrUrl!,
            interfaces: c.lanInterfaces,
            selectedInterface: c.selectedLanInterface,
            onSelectInterface: c.selectLanInterface,
            hintText:
                'Работает внутри одной сети Wi-Fi даже без интернета (через «Луч» или обычный браузер).',
            onStop: c.stopLanServer,
          ),
        ],
        if (c.statusError != null) ...[
          const SizedBox(height: 14),
          _StatusBanner(
            message: c.statusError!,
            isError: true,
            onDismiss: c.clearStatusMessages,
          ),
        ],
        if (c.notice != null) ...[
          const SizedBox(height: 14),
          _StatusBanner(
            message: c.notice!,
            isError: false,
            onDismiss: c.clearStatusMessages,
          ),
        ],
        if (files.isNotEmpty && c.sendMode == SendContentMode.files) ...[
          const SizedBox(height: 18),
          Text(
            'В очереди: ${files.length} файл. (${formatBytes(totalSize)})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < files.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: isDark ? AppTheme.border : AppTheme.lightBorder,
                    ),
                  ListTile(
                    leading: Icon(Icons.insert_drive_file_outlined,
                        color: cs.primary),
                    title: Text(
                      files[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(formatBytes(files[i].size)),
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
              Text('Прогресс отправки',
                  style: Theme.of(context).textTheme.titleSmall),
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

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.title,
    required this.subtitle,
    required this.onCancel,
  });

  final String title;
  final String subtitle;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            TextButton(onPressed: onCancel, child: const Text('Отменить')),
          ],
        ),
      ),
    );
  }
}

class _ActiveSessionBanner extends StatelessWidget {
  const _ActiveSessionBanner({
    required this.controller,
    required this.onPickMoreFiles,
  });

  final LuchController controller;
  final VoidCallback onPickMoreFiles;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_rounded,
                    color: AppTheme.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.peerName ?? 'Подключено',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        switch (c.phase) {
                          WebRtcPhase.transferring => 'Идёт передача...',
                          WebRtcPhase.done => 'Передача завершена',
                          _ => 'Защищённый канал WebRTC открыт',
                        },
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: c.resetWebRtcSession,
                  child: const Text('Отключиться'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (c.phase == WebRtcPhase.transferring)
                  OutlinedButton.icon(
                    onPressed: c.cancelActiveTransfer,
                    icon: const Icon(Icons.stop_circle_outlined,
                        color: AppTheme.danger),
                    label: const Text('Отменить передачу'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: onPickMoreFiles,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Отправить ещё файлы'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppTheme.danger : AppTheme.success;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline,
            color: color,
          ),
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
