import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';
import 'auth_service.dart';

/// Records errors people actually hit into `app_error_logs`, so a report like
/// "Devaraj gets an error when he drops a property" can be answered from the
/// log (who, when, which screen, and the real database/auth error) instead of
/// from a screenshot of a generic toast.
///
/// Captured automatically: uncaught Flutter/zone errors (main.dart), every
/// AppFeedback.error toast shown to a user, and login failures. Call [capture]
/// from a catch block that would otherwise swallow the real cause.
///
/// Never throws and never shows UI — logging must not be able to break the
/// flow it is observing. Identical errors are throttled, and a session stops
/// logging after [_maxPerSession] entries.
class ErrorLogService {
  ErrorLogService._();

  static const _table = 'app_error_logs';
  static const _maxPerSession = 60;
  static const _dedupeWindow = Duration(seconds: 30);

  /// Commit the build was made from (set by scripts/vercel-build.js).
  static const appBuild = String.fromEnvironment('APP_BUILD');

  static int _sent = 0;
  static final Map<String, DateTime> _recent = {};

  /// Logs [error]. [action] names what the user was doing (e.g.
  /// 'drop_request_submit'); [source] says how it was caught.
  static Future<void> capture(
    Object error, {
    StackTrace? stack,
    String action = '',
    String source = 'caught',
    String? message,
    String? emailOverride,
  }) async {
    try {
      final summary = message ?? _messageOf(error);
      final key = '$source|$action|$summary';
      final now = DateTime.now();
      final last = _recent[key];
      if (last != null && now.difference(last) < _dedupeWindow) return;
      if (_sent >= _maxPerSession) return;
      _recent[key] = now;
      _sent++;

      final auth = AuthService.instance;
      final user = auth.currentUser;
      final details = <String>[
        ..._detailsOf(error),
        if (auth.isImpersonating) 'Accessing as user (real session: management)',
      ].join('\n');

      await Supabase.instance.client.from(_table).insert({
        'user_email': _clip(
            (emailOverride ?? user?.email ?? '').trim().toLowerCase(), 200),
        'user_name': _clip(user?.fullName ?? '', 200),
        'source': _clip(source, 40),
        'action': _clip(action, 120),
        'screen': _clip(_screen(), 300),
        'error_type': _clip(error.runtimeType.toString(), 120),
        'message': _clip(summary, 2000),
        'details': _clip(details, 4000),
        'stack': _clip(stack?.toString() ?? '', 6000),
        'platform': _clip(_platform(), 60),
        'app_build': _clip(appBuild, 60),
      });
    } catch (e) {
      debugPrint('[error-log] could not record error: $e');
    }
  }

  /// Logs an error message that was shown to the user with no exception
  /// object attached (AppFeedback.error).
  static Future<void> captureShown(String message) =>
      capture(message, source: 'shown_to_user', message: message);

  /// Newest entries first — admin-only by RLS (others get an empty list).
  static Future<List<AppErrorLogEntry>> recent({int limit = 300}) async {
    final rows = await Supabase.instance.client
        .from(_table)
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => AppErrorLogEntry.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  static String _messageOf(Object error) {
    if (error is PostgrestException) return error.message;
    if (error is AuthException) return error.message;
    if (error is ApiException) return error.message;
    if (error is String) return error;
    return error.toString();
  }

  static List<String> _detailsOf(Object error) {
    if (error is PostgrestException) {
      return [
        if (error.code != null) 'Postgres code: ${error.code}',
        if (error.details != null) 'Details: ${error.details}',
        if (error.hint != null) 'Hint: ${error.hint}',
      ];
    }
    if (error is AuthException) {
      return [
        if (error.statusCode != null) 'HTTP status: ${error.statusCode}',
        if (error.code != null) 'Auth code: ${error.code}',
      ];
    }
    if (error is ApiException) return ['Status: ${error.statusCode}'];
    return const [];
  }

  /// Current route, e.g. "/land-lead" (hash routing on web).
  static String _screen() {
    try {
      final base = Uri.base;
      if (base.fragment.isNotEmpty) return base.fragment;
      return base.path;
    } catch (_) {
      return '';
    }
  }

  static String _platform() {
    final os = defaultTargetPlatform.name;
    return kIsWeb ? 'web ($os)' : os;
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}

/// One row of `app_error_logs`.
class AppErrorLogEntry {
  final String id;
  final DateTime createdAt;
  final String userEmail;
  final String userName;
  final String source;
  final String action;
  final String screen;
  final String errorType;
  final String message;
  final String details;
  final String stack;
  final String platform;
  final String appBuild;

  const AppErrorLogEntry({
    required this.id,
    required this.createdAt,
    this.userEmail = '',
    this.userName = '',
    this.source = '',
    this.action = '',
    this.screen = '',
    this.errorType = '',
    this.message = '',
    this.details = '',
    this.stack = '',
    this.platform = '',
    this.appBuild = '',
  });

  /// Name, else email, else "Not signed in".
  String get who => userName.trim().isNotEmpty
      ? userName.trim()
      : (userEmail.trim().isNotEmpty ? userEmail.trim() : 'Not signed in');

  /// Everything in one block, for copying into a bug report.
  String get fullText => [
        'Time: ${createdAt.toLocal()}',
        'User: $who${userEmail.isNotEmpty ? ' <$userEmail>' : ''}',
        'Source: $source${action.isNotEmpty ? ' · $action' : ''}',
        if (screen.isNotEmpty) 'Screen: $screen',
        if (platform.isNotEmpty) 'Platform: $platform',
        if (appBuild.isNotEmpty) 'Build: $appBuild',
        if (errorType.isNotEmpty) 'Type: $errorType',
        'Message: $message',
        if (details.isNotEmpty) details,
        if (stack.isNotEmpty) 'Stack:\n$stack',
      ].join('\n');

  factory AppErrorLogEntry.fromRow(Map<String, dynamic> r) {
    String s(String k) => (r[k] as String?) ?? '';
    return AppErrorLogEntry(
      id: r['id'].toString(),
      createdAt:
          DateTime.tryParse(s('created_at'))?.toLocal() ?? DateTime.now(),
      userEmail: s('user_email'),
      userName: s('user_name'),
      source: s('source'),
      action: s('action'),
      screen: s('screen'),
      errorType: s('error_type'),
      message: s('message'),
      details: s('details'),
      stack: s('stack'),
      platform: s('platform'),
      appBuild: s('app_build'),
    );
  }
}
