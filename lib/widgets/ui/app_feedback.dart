import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';

/// Semantic tone for a feedback toast.
enum FeedbackTone { success, error, info, warning }

/// ============================================================================
/// Standardized, typed toast/snackbar feedback.
///
/// Replaces raw `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))`
/// call sites with a one-liner that carries a semantic tone (colour + icon):
///
/// ```dart
/// AppFeedback.success(context, 'Lead updated');
/// AppFeedback.error(context, 'Could not update status: $e');
/// AppFeedback.info(context, 'Management view is read-only');
/// ```
///
/// Pure presentation — no business logic. Every toast is a floating, rounded,
/// theme-aware surface with a coloured leading icon chip, an optional action,
/// and an accessible live-region announcement.
/// ============================================================================
class AppFeedback {
  const AppFeedback._();

  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) =>
      _show(context, message, FeedbackTone.success,
          actionLabel: actionLabel, onAction: onAction, duration: duration);

  /// Also records [message] in the error log (ErrorLogService) — every error
  /// a user is shown becomes a log entry with who, when and which screen.
  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    ErrorLogService.captureShown(message);
    _show(context, message, FeedbackTone.error,
        actionLabel: actionLabel, onAction: onAction, duration: duration);
  }

  static void info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) =>
      _show(context, message, FeedbackTone.info,
          actionLabel: actionLabel, onAction: onAction, duration: duration);

  static void warning(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) =>
      _show(context, message, FeedbackTone.warning,
          actionLabel: actionLabel, onAction: onAction, duration: duration);

  /// A failure the user has to read and act on, shown as a dialog rather than a
  /// toast — a toast fades after ~4s and takes the reason with it, which is no
  /// use when the reason is a paragraph explaining what to go and fix. The text
  /// is selectable and copyable so it can be pasted into a bug report.
  static Future<void> errorDetails(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    ErrorLogService.captureShown('$title: $message');
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.fomraSurface,
        icon: const Icon(Icons.error_outline_rounded, color: AppColors.error),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: ctx.fomraTextPrimary,
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: SelectableText(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: ctx.fomraTextSecondary,
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Color _color(FeedbackTone tone) {
    switch (tone) {
      case FeedbackTone.success:
        return AppColors.success;
      case FeedbackTone.error:
        return AppColors.error;
      case FeedbackTone.info:
        return AppColors.info;
      case FeedbackTone.warning:
        return AppColors.warning;
    }
  }

  static IconData _icon(FeedbackTone tone) {
    switch (tone) {
      case FeedbackTone.success:
        return Icons.check_circle_rounded;
      case FeedbackTone.error:
        return Icons.error_rounded;
      case FeedbackTone.info:
        return Icons.info_rounded;
      case FeedbackTone.warning:
        return Icons.warning_rounded;
    }
  }

  static void _show(
    BuildContext context,
    String message,
    FeedbackTone tone, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final tokenColor = _color(tone);
    final isDark = context.isDarkMode;
    final surface = context.fomraSurface;
    final textColor = context.fomraTextPrimary;

    final defaultDuration = (tone == FeedbackTone.error ||
            tone == FeedbackTone.warning)
        ? const Duration(seconds: 4)
        : const Duration(seconds: 3);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface,
        elevation: 0,
        duration: duration ?? defaultDuration,
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          side: BorderSide(
            color: tokenColor.withValues(alpha: isDark ? 0.55 : 0.35),
          ),
        ),
        content: Semantics(
          liveRegion: true,
          container: true,
          label: '${tone.name}: $message',
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tokenColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppColors.radiusXs),
                ),
                child: Icon(_icon(tone), color: tokenColor, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        action: (actionLabel != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: tokenColor,
                onPressed: onAction ?? () {},
              )
            : null,
      ),
    );
  }
}
