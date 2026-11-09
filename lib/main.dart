import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_link.dart';
import 'services/auth_service.dart';
import 'services/error_log_service.dart';
import 'services/app_settings_service.dart';
import 'services/session_scoped_local_storage.dart';
import 'services/push_service.dart';
import 'services/offline_sync_service.dart';
import 'services/lead_drop_reason_catalog_service.dart';
import 'services/profile_photo_service.dart';
import 'services/supabase_config.dart';
import 'services/theme_controller.dart';
import 'services/role_access.dart';
import 'services/view_scope.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/set_password_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/land_lead/land_workspace_screen.dart';
import 'screens/market_intelligence/market_intelligence_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/audit/audit_trail_screen.dart';
import 'screens/notifications/notification_center_screen.dart';
import 'screens/task_management/task_management_screen.dart';
import 'screens/settings/change_password_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/broker/broker_management_screen.dart';
import 'screens/legal/legal_tracker_screen.dart';
import 'screens/legal_verification/legal_verification_screen.dart';
import 'screens/survey/survey_tracker_screen.dart';
import 'screens/owner/owner_history_screen.dart';
import 'screens/cost/cost_calculator_screen.dart';

void main() {
  // Snapshot the launch URL before Flutter's hash router can rewrite the
  // fragment (invite / recovery tokens live there).
  AuthLink.capture();
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Keep Flutter's own console output, and also record the error in
    // app_error_logs so it is visible without access to the user's device.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      ErrorLogService.capture(
        details.exception,
        stack: details.stack,
        source: 'flutter',
        action: details.context?.toDescription() ?? '',
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      ErrorLogService.capture(error, stack: stack, source: 'uncaught');
      return true;
    };
    await ThemeController.instance.load();
    // Restore the Reporting Manager / Head Team-vs-Individual selection before
    // the first frame so their view doesn't flip after load.
    await ViewScope.instance.load();
    runApp(const FomraLSApp());
  }, (error, stack) {
    debugPrint('ZONE ERROR: $error\n$stack');
    ErrorLogService.capture(error, stack: stack, source: 'uncaught');
  });
}

/// Top-level modules a web reload may return to. Excludes auth routes
/// (`/login`, `/set-password`, `/change-password`) so a reload never strands
/// the user mid-auth. Keep in sync with the `routes` map below.
const Set<String> _restorableRoutes = {
  '/home',
  '/employee-portal',
  '/management-portal',
  '/land-lead',
  '/employee-management',
  '/task-management',
  '/market-intelligence',
  '/legal-verification',
  '/broker-management',
  '/legal-tracker',
  '/survey-tracker',
  '/owner-history',
  '/cost-calculator',
  '/reports',
  '/notifications',
  '/audit-trail',
  '/settings',
};

class FomraLSApp extends StatelessWidget {
  const FomraLSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'Fomra LandIQ',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        darkTheme: appThemeDark(),
        themeMode: themeMode,
        // Slightly larger global type (~8%) without touching per-widget sizes,
        // so existing spacing/layout is preserved. Still honours the OS
        // accessibility setting, just with a raised floor.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 1.08,
                maxScaleFactor: 1.3,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const _StartupScreen(),
        // On web, a page reload hands Flutter the URL's route directly. Always
        // boot the splash instead, so Supabase/session restore first and the
        // real page is rebuilt with a live session (see _StartupScreen._init,
        // which then re-opens the route the URL points at).
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute(builder: (_) => const _StartupScreen()),
        ],
        routes: {
          '/login':               (_) => const LoginScreen(),
          '/set-password':        (_) => const SetPasswordScreen(),
          '/home':                (_) => const HomeScreen(),
          '/employee-portal':     (_) => const TaskManagementScreen(
                                      portalMode: TaskPortalMode.employee),
          '/management-portal':   (_) => const TaskManagementScreen(
                                      portalMode: TaskPortalMode.management),
          '/land-lead':           (_) => const LandWorkspaceScreen(initialTab: 0),
          '/employee-management': (_) => const SettingsScreen(),
          '/task-management':     (_) => const TaskManagementScreen(),
          '/market-intelligence': (_) => const MarketIntelligenceScreen(),
          '/legal-verification':  (_) => const LegalVerificationScreen(),
          '/broker-management':   (_) => const BrokerManagementScreen(),
          '/legal-tracker':       (_) => const LegalTrackerScreen(),
          '/survey-tracker':      (_) => const SurveyTrackerScreen(),
          '/owner-history':       (_) => const OwnerHistoryScreen(),
          '/cost-calculator':     (_) => const CostCalculatorScreen(),
          '/reports':             (_) => const ReportsScreen(),
          '/notifications':       (_) => const NotificationCenterScreen(),
          '/audit-trail':         (_) => RoleAccess.canViewAudit
                                      ? const AuditTrailScreen()
                                      : const HomeScreen(),
          '/settings':            (_) => const SettingsScreen(),
          '/change-password':     (_) => const ChangePasswordScreen(),
        },
      ),
    );
  }
}

/// Initializes Supabase then navigates to /login.
/// Shows a spinner while connecting and an error box (with Retry) on failure.
class _StartupScreen extends StatefulWidget {
  const _StartupScreen();

  @override
  State<_StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<_StartupScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (mounted) setState(() => _error = null);
    String? error;
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseAnon,
        authOptions: const FlutterAuthClientOptions(
          detectSessionInUri: false,
          // Per-tab session persistence so different tabs can hold different
          // accounts (Management vs Employee) at the same time.
          localStorage: SessionScopedLocalStorage(
            persistSessionKey: 'fomrals-supabase-session',
          ),
        ),
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw 'Connection timed out.\nCheck your internet and try again.',
      );
    } catch (e) {
      error = e.toString();
    }
    // Bring up Firebase push in the background — fully guarded, never blocks or
    // crashes startup if Firebase isn't configured on this platform.
    if (error == null) unawaited(PushService.init());
    if (error == null) unawaited(OfflineSyncService.instance.start());
    if (error == null) unawaited(LeadDropReasonCatalogService.instance.load());
    if (error == null) unawaited(ProfilePhotoService.instance.load());
    if (error == null) unawaited(AppSettingsService.instance.reload());
    bool loggedIn = false;
    if (error == null) {
      try {
        loggedIn = await AuthService.instance.checkSession();
      } catch (_) {
        loggedIn = false;
      }
    }

    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
    } else if (AuthLink.isAuthCallback) {
      // Arrived from an invite / password-recovery email link.
      Navigator.of(context).pushReplacementNamed('/set-password');
    } else if (!loggedIn) {
      Navigator.of(context).pushReplacementNamed('/login');
    } else {
      // Land on /home, then — on a web reload — re-open the module the URL
      // still points at, layered on top so Home > Module breadcrumbs and the
      // back button keep working. Sub-views opened over a module (e.g. a lead
      // detail) aren't in the URL, so reload returns to the module page.
      final nav = Navigator.of(context)..pushReplacementNamed('/home');
      final target = _restoreRoute();
      if (target != null && target != '/home') nav.pushNamed(target);
    }
  }

  /// The named route the app was reloaded on (hash fragment on web), limited to
  /// safe top-level modules — never an auth route. Null when there's nothing to
  /// restore or the fragment isn't a known module.
  String? _restoreRoute() {
    final frag = AuthLink.initialUri.fragment;
    if (frag.isEmpty) return null;
    final path = (frag.startsWith('/') ? frag : '/$frag').split('?').first;
    return _restorableRoutes.contains(path) ? path : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2563EB),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Fomra LandIQ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Fomra Housing Pvt. Ltd.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 48),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_off_outlined,
                          color: Colors.white70, size: 28),
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _init,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF2563EB),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      color: Colors.white54, strokeWidth: 2.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Connecting…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
