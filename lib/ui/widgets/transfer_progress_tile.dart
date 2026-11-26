import 'package:material_ui/material_ui.dart';

import '../../core/protocol/transfer_models.dart';
import '../theme/app_theme.dart';

class TransferProgressTile extends StatelessWidget {
  const TransferProgressTile({super.key, required this.progress});

  final TransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final isSend = progress.direction == TransferDirection.sent;
    final statusColor = switch (progress.status) {
      TransferStatus.completed => AppTheme.success,
      TransferStatus.failed => AppTheme.danger,
      TransferStatus.transferring => cs.primary,
      TransferStatus.pending => Theme.of(context).hintColor,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceAlt : AppTheme.lightSurfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.border : AppTheme.lightBorder,
        ),
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
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusText(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
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
              backgroundColor: isDark ? AppTheme.bg : AppTheme.lightBg,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${formatBytes(progress.bytesTransferred)} / ${formatBytes(progress.totalBytes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (progress.peerLabel != null)
                Text(
                  progress.peerLabel!,
                  style: Theme.of(context).textTheme.bodySmall,
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
        return progress.speedBytesPerSec > 0
            ? formatSpeed(progress.speedBytesPerSec)
            : '${(progress.fraction * 100).round()}%';
      case TransferStatus.completed:
        return 'Готово';
      case TransferStatus.failed:
        return 'Ошибка';
    }
  }
}
