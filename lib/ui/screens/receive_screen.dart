import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

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
  final TextEditingController _urlController = TextEditingController();
  bool _isDraggingQr = false;

  bool get _supportsLiveCamera =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _scanWithCamera() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerSheet()),
    );
    if (result != null && result.isNotEmpty) {
      _urlController.text = result;
      await widget.controller.connectToQrPayload(result);
    }
  }

  Future<void> _decodeQrFromImagePath(String path) async {
    final decoded = await QrImageDecoder.decodeFile(File(path));
    if (!mounted) return;
    if (decoded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('На изображении не удалось распознать QR-код.'),
        ),
      );
      return;
    }
    _urlController.text = decoded;
    await widget.controller.connectToQrPayload(decoded);
  }

  Future<void> _pickQrImage() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Выберите изображение или скриншот с QR-кодом',
      type: FileType.image,
    );
    final path = picked?.path;
    if (path != null) {
      await _decodeQrFromImagePath(path);
    }
  }

  Future<void> _pickFilesToPushToPeer() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Выберите файлы для отправки на принимающее устройство',
    );
    if (picked.isEmpty) return;
    final paths =
        picked.map((f) => f.path).whereType<String>().toList(growable: false);
    if (paths.isNotEmpty) {
      await widget.controller.uploadFilesToConnectedPeer(paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
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
                    const Icon(Icons.qr_code_scanner_rounded,
                        color: AppTheme.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Подключиться по QR отправителя',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _supportsLiveCamera
                      ? 'Отсканируйте QR-код камерой, откройте картинку с QR или вставьте ссылку сессии.'
                      : 'Откройте картинку/скриншот с QR-кодом, перетащите его сюда или вставьте ссылку сессии.',
                  style: const TextStyle(fontSize: 13, color: Colors.white60),
                ),
                const SizedBox(height: 14),
                DropTarget(
                  enable: _isDesktop,
                  onDragEntered: (_) => setState(() => _isDraggingQr = true),
                  onDragExited: (_) => setState(() => _isDraggingQr = false),
                  onDragDone: (details) async {
                    setState(() => _isDraggingQr = false);
                    if (details.files.isNotEmpty) {
                      await _decodeQrFromImagePath(details.files.first.path);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _isDraggingQr
                          ? AppTheme.accent.withValues(alpha: 0.12)
                          : AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isDraggingQr ? AppTheme.accent : AppTheme.border,
                      ),
                    ),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (_supportsLiveCamera)
                              ElevatedButton.icon(
                                onPressed:
                                    c.isConnecting ? null : _scanWithCamera,
                                icon: const Icon(Icons.camera_alt_rounded),
                                label: const Text('Сканировать камерой'),
                              ),
                            FilledButton.tonalIcon(
                              onPressed: c.isConnecting ? null : _pickQrImage,
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
                                controller: _urlController,
                                decoration: const InputDecoration(
                                  hintText: 'http://192.168.1.10:54321/s/...',
                                  labelText: 'Или вставьте ссылку из QR',
                                  isDense: true,
                                ),
                                onSubmitted: (val) => c.connectToQrPayload(val),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: c.isConnecting
                                  ? null
                                  : () => c.connectToQrPayload(
                                        _urlController.text,
                                      ),
                              child: c.isConnecting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF061322),
                                      ),
                                    )
                                  : const Text('Открыть'),
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
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
                const SizedBox(width: 10),
                Expanded(child: Text(c.statusError!)),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: c.clearError,
                ),
              ],
            ),
          ),
        ],
        if (c.connectedSession != null) ...[
          const SizedBox(height: 16),
          _ConnectedPeerCard(
            session: c.connectedSession!,
            isBusy: c.isTransferringClient,
            saveDirectoryPath: c.saveDirectoryPath,
            onDownloadAll: () =>
                c.downloadRemoteFiles(c.connectedSession!.files),
            onDownloadSingle: (file) => c.downloadRemoteFiles([file]),
            onPushFiles: _pickFilesToPushToPeer,
            onDisconnect: c.disconnectPeer,
          ),
        ],
        const SizedBox(height: 18),
        if (!c.isHostingReceive)
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              leading: const CircleAvatar(
                backgroundColor: AppTheme.surfaceAlt,
                child: Icon(Icons.qr_code_rounded, color: AppTheme.amber),
              ),
              title: const Text(
                'Показать мой QR для приёма файлов',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Удобно, если на другом устройстве камера — просто отсканируйте этот QR и отправьте файлы сюда.',
              ),
              trailing: ElevatedButton(
                onPressed: c.startReceiveHostSession,
                child: const Text('Включить'),
              ),
            ),
          )
        else if (c.activeQrUrl != null)
          QrSessionCard(
            title: 'Ожидание входящих файлов',
            subtitle: 'Сохранение в: ${c.saveDirectoryPath}',
            qrUrl: c.activeQrUrl!,
            interfaces: c.interfaces,
            selectedInterface: c.selectedInterface,
            onSelectInterface: c.selectInterface,
            onStop: c.stopServer,
          ),
        if (receiveProgress.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Прогресс передачи',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Colors.white70),
              ),
              TextButton(
                onPressed: c.clearCompletedTransfers,
                child: const Text('Очистить'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in receiveProgress)
            TransferProgressTile(progress: item),
        ],
      ],
    );
  }
}

class _ConnectedPeerCard extends StatelessWidget {
  const _ConnectedPeerCard({
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
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        session.mode == SessionMode.send
                            ? 'Готов к передаче (${session.files.length} файл.)'
                            : 'Готов принимать файлы от вас',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
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
            const SizedBox(height: 12),
            if (session.mode == SessionMode.send) ...[
              Text(
                'Папка сохранения: $saveDirectoryPath',
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
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
              const SizedBox(height: 10),
              for (final file in session.files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_outlined,
                      color: AppTheme.accent),
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(formatBytes(file.sizeBytes)),
                  trailing: IconButton(
                    tooltip: 'Скачать файл',
                    onPressed: isBusy ? null : () => onDownloadSingle(file),
                    icon: const Icon(Icons.download_rounded,
                        color: AppTheme.accent),
                  ),
                ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: isBusy ? null : onPushFiles,
                icon: const Icon(Icons.send_rounded),
                label: Text(
                  isBusy ? 'Отправка...' : 'Выбрать файлы и отправить',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
