import 'package:flutter/material.dart';

import '../services/offline_sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';

/// Compact banner showing offline / pending-sync status.
class OfflineStatusBanner extends StatelessWidget {
  const OfflineStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: OfflineSyncService.instance,
      builder: (context, _) {
        final sync = OfflineSyncService.instance;
        if (sync.isOnline && sync.pendingCount == 0 && !sync.isSyncing) {
          return const SizedBox.shrink();
        }

        final offline = !sync.isOnline;
        // Something keeps failing (not just waiting for signal): say so,
        // plainly, so it isn't left unseen. It keeps retrying, and the
        // reason is in the error log.
        final failed = sync.failedCount > 0 && !sync.isSyncing;
        final color = failed
            ? AppColors.error
            : offline
                ? AppColors.warning
                : (sync.isSyncing ? AppColors.info : AppColors.primary);
        final n = sync.pendingCount;
        final text = failed
            ? '${sync.failedCount} saved item${sync.failedCount == 1 ? '' : 's'} '
                "couldn't upload yet — tap to retry"
            : offline
                ? 'No signal · $n saved on this phone — will upload '
                    'automatically'
                : sync.isSyncing
                    ? 'Uploading saved field data…'
                    : '$n saved on this phone, uploading…';

        return Material(
          color: color.withValues(alpha: 0.12),
          child: InkWell(
            onTap: sync.isOnline && !sync.isSyncing
                ? () => sync.syncNow()
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    failed
                        ? Icons.error_outline_rounded
                        : offline
                            ? Icons.cloud_off_rounded
                            : Icons.cloud_sync_rounded,
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                  ),
                  if (sync.isOnline &&
                      sync.pendingCount > 0 &&
                      !sync.isSyncing)
                    Text(
                      'Tap to sync',
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
