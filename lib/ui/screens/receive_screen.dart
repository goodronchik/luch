import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/file_io_adapter.dart';
import '../../core/platform/platform_info.dart';
import '../../core/protocol/transfer_models.dart';
import '../../core/qr/qr_image_decoder.dart';
import '../../state/luch_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/qr_scanner_sheet.dart';
import '../widgets/qr_session_card.dart';
import '../widgets/transfer_progress_tile.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key, required this.controller});

  final LuchController controller;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final TextEditingController _inputController = TextEditingController();
  bool _isDraggingQr = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _scanWithCamera() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerSheet()),
    );
    if (result != null && result.isNotEmpty) {
      _inputController.clear();
      await widget.controller.connectWithInput(result);
    }
  }

  Future<void> _decodeQrBytes(Uint8List bytes) async {
    final decoded = QrImageDecoder.decodeBytes(bytes);
    if (!mounted) return;
    if (decoded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('На изображении не удалось распознать QR-код.'),
        ),
      );
      return;
    }
    _inputController.clear();
    await widget.controller.connectWithInput(decoded);
  }

  Future<void> _submitManualInput([String? overrideValue]) async {
    final raw = (overrideValue ?? _inputController.text).trim();
    if (raw.isEmpty) return;
    _inputController.clear();
    FocusScope.of(context).unfocus();
    await widget.controller.connectWithInput(raw);
  }

  Future<void> _openReceivedFile(String? path) async {
    final err = await widget.controller.openReceivedFile(path);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  Future<void> _pickQrImage() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Выберите изображение или скриншот с QR-кодом',
      type: FileType.image,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await _decodeQrBytes(bytes);
  }

  Future<void> _pickFilesToPushLan() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Выберите файлы для отправки на устройство',
    );
    if (picked.isEmpty) return;
    final sources = await PlatformFileStorage.sourcesFromPlatformFiles(picked);
    if (sources.isNotEmpty) {
      await widget.controller.uploadLanFiles(sources);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final receiveProgress = c.transfers;

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
                    Icon(Icons.qr_code_scanner_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Получить файлы или текст',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Отсканируйте QR-код, выберите скриншот с QR или введите 24-символьный код вручную.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                DropTarget(
                  enable: PlatformInfo.isDesktopNative || PlatformInfo.isWeb,
                  onDragEntered: (_) => setState(() => _isDraggingQr = true),
                  onDragExited: (_) => setState(() => _isDraggingQr = false),
                  onDragDone: (details) async {
                    setState(() => _isDraggingQr = false);
                    if (details.files.isNotEmpty) {
                      final bytes = await details.files.first.readAsBytes();
                      await _decodeQrBytes(bytes);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _isDraggingQr
                          ? cs.primary.withValues(alpha: 0.12)
                          : (isDark
                              ? AppTheme.surfaceAlt
                              : AppTheme.lightSurfaceAlt),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isDraggingQr
                            ? cs.primary
                            : (isDark ? AppTheme.border : AppTheme.lightBorder),
                      ),
                    ),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (PlatformInfo.supportsLiveCamera)
                              ElevatedButton.icon(
                                onPressed: c.phase == WebRtcPhase.connecting
                                    ? null
                                    : _scanWithCamera,
                                icon: const Icon(Icons.camera_alt_rounded),
                                label: const Text('Сканировать QR'),
                              ),
                            FilledButton.tonalIcon(
                              onPressed: c.phase == WebRtcPhase.connecting
                                  ? null
                                  : _pickQrImage,
                              icon: const Icon(Icons.image_search_rounded),
                              label: const Text('QR из картинки'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _inputController,
                                decoration: const InputDecoration(
                                  hintText:
                                      'XXXXXX-XXXXXX-XXXXXX-XXXXXX или ссылка',
                                  labelText: 'Код или ссылка из QR',
                                  isDense: true,
                                ),
                                onSubmitted: (val) => _submitManualInput(val),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: c.phase == WebRtcPhase.connecting
                                  ? null
                                  : _submitManualInput,
                              child: c.phase == WebRtcPhase.connecting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Войти'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (c.statusError != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
                const SizedBox(width: 10),
                Expanded(child: Text(c.statusError!)),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: c.clearStatusMessages,
                ),
              ],
            ),
          ),
        ],
        if (c.pendingOffer != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Входящие файлы от «${c.pendingOffer!.senderName}»',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Файлов: ${c.pendingOffer!.entries.length} • ${formatBytes(c.pendingOffer!.totalBytes)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  for (final entry in c.pendingOffer!.entries)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.insert_drive_file_outlined,
                          color: cs.primary),
                      title: Text(entry.name),
                      trailing: Text(formatBytes(entry.size)),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: c.acceptIncomingOffer,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Принять'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: c.rejectIncomingOffer,
                        child: const Text('Отклонить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        if (c.incomingText != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notes_rounded, color: AppTheme.success),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Полученный текст',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Скопировать',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: c.incomingText!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Текст скопирован')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: c.clearIncomingText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.surfaceAlt
                          : AppTheme.lightSurfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(c.incomingText!),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (c.connectedLanSession != null) ...[
          const SizedBox(height: 16),
          _LanPeerCard(
            session: c.connectedLanSession!,
            isBusy: c.isLanTransferring,
            saveDirectoryPath: c.saveDirectoryDisplay,
            onDownloadAll: () =>
                c.downloadLanFiles(c.connectedLanSession!.files),
            onDownloadSingle: (f) => c.downloadLanFiles([f]),
            onPushFiles: _pickFilesToPushLan,
            onDisconnect: c.disconnectLanPeer,
          ),
        ],
        if (c.supportsLocalLan) ...[
          const SizedBox(height: 18),
          if (!c.isLanHostingReceive)
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                leading: CircleAvatar(
                  backgroundColor:
                      isDark ? AppTheme.surfaceAlt : AppTheme.lightSurfaceAlt,
                  child: const Icon(Icons.wifi_rounded, color: AppTheme.amber),
                ),
                title: const Text(
                  'Принять локально по Wi-Fi (мой QR)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Работает без интернета — отсканируйте этот QR любым устройством или браузером в одной сети.',
                ),
                trailing: ElevatedButton(
                  onPressed: c.startLanReceiveHost,
                  child: const Text('Включить'),
                ),
              ),
            )
          else if (c.activeLanQrUrl != null)
            QrSessionCard(
              title: 'Ожидание входящих файлов по Wi-Fi',
              subtitle: 'Сохранение в: ${c.saveDirectoryDisplay}',
              qrUrl: c.activeLanQrUrl!,
              interfaces: c.lanInterfaces,
              selectedInterface: c.selectedLanInterface,
              onSelectInterface: c.selectLanInterface,
              onStop: c.stopLanServer,
            ),
        ],
        if (receiveProgress.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Передачи', style: Theme.of(context).textTheme.titleSmall),
              TextButton(
                onPressed: c.clearCompletedTransfers,
                child: const Text('Очистить'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in receiveProgress)
            TransferProgressTile(
              progress: item,
              onTapOpen: item.savedPath != null
                  ? () => _openReceivedFile(item.savedPath)
                  : null,
            ),
        ],
      ],
    );
  }
}

class _LanPeerCard extends StatelessWidget {
  const _LanPeerCard({
    required this.session,
    required this.isBusy,
    required this.saveDirectoryPath,
    required this.onDownloadAll,
    required this.onDownloadSingle,
    required this.onPushFiles,
    required this.onDisconnect,
  });

  final SessionInfo session;
  final bool isBusy;
  final String saveDirectoryPath;
  final VoidCallback onDownloadAll;
  final ValueChanged<SharedFileItem> onDownloadSingle;
  final VoidCallback onPushFiles;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices_rounded, color: AppTheme.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.deviceName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        session.mode == SessionMode.send
                            ? 'Wi-Fi раздача (${session.files.length} файл.)'
                            : 'Wi-Fi приёмник',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onDisconnect,
                  child: const Text('Отключиться'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (session.mode == SessionMode.send) ...[
              Text('Папка сохранения: $saveDirectoryPath',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              if (session.files.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: isBusy ? null : onDownloadAll,
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: Text(
                    isBusy
                        ? 'Идёт загрузка...'
                        : 'Скачать все (${session.files.length})',
                  ),
                ),
              const SizedBox(height: 8),
              for (final file in session.files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.insert_drive_file_outlined,
                      color: cs.primary),
                  title: Text(file.name),
                  subtitle: Text(formatBytes(file.sizeBytes)),
                  trailing: IconButton(
                    onPressed: isBusy ? null : () => onDownloadSingle(file),
                    icon: Icon(Icons.download_rounded, color: cs.primary),
                  ),
                ),
            ] else
              ElevatedButton.icon(
                onPressed: isBusy ? null : onPushFiles,
                icon: const Icon(Icons.send_rounded),
                label: Text(
                    isBusy ? 'Отправка...' : 'Выбрать файлы и отправить'),
              ),
          ],
        ),
      ),
    );
  }
}
