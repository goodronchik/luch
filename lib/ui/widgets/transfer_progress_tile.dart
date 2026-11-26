import 'package:material_ui/material_ui.dart';

import '../../core/protocol/transfer_models.dart';
import '../theme/app_theme.dart';

class TransferProgressTile extends StatelessWidget {
  const TransferProgressTile({super.key, required this.progress});

  final TransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final isSend = progress.direction == TransferDirection.sent;
    final statusColor = switch (progress.status) {
      TransferStatus.completed => AppTheme.success,
      TransferStatus.failed => AppTheme.danger,
      TransferStatus.transferring => AppTheme.accent,
      TransferStatus.pending => Colors.white54,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSend ? Icons.upload_rounded : Icons.download_rounded,
                size: 18,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  progress.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusText(),
                style: TextStyle(fontSize: 12, color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.status == TransferStatus.completed
                  ? 1.0
                  : progress.fraction,
              minHeight: 6,
              backgroundColor: AppTheme.bg,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${formatBytes(progress.bytesTransferred)} / ${formatBytes(progress.totalBytes)}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              if (progress.peerLabel != null)
                Text(
                  progress.peerLabel!,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
            ],
          ),
          if (progress.errorMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              progress.errorMessage!,
              style: const TextStyle(fontSize: 11, color: AppTheme.danger),
            ),
          ],
        ],
      ),
    );
  }

  String _statusText() {
    switch (progress.status) {
      case TransferStatus.pending:
        return 'Ожидание';
      case TransferStatus.transferring:
        return formatSpeed(progress.speedBytesPerSec);
      case TransferStatus.completed:
        return 'Готово';
      case TransferStatus.failed:
        return 'Ошибка';
    }
  }
}
