import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee_profile.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'employee_service.dart';
import 'tab_session_store.dart';

enum LoginPortal { employee, management }

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const _portalKey = 'login_portal';
  static const _localSessionKey = 'local_auth_session';
  static const _loginEmailKey = 'login_email';
  static const _loginNameKey = 'login_display_name';
  static const _loginAtKey = 'login_at';

  /// After a successful login the session is kept alive for at least this long,
  /// even across reloads, regardless of whether the Supabase session rehydrates.
  static const _sessionGrace = Duration(minutes: 5);

  static const managementEmail = 'management@fomrahousing.in';
  static const employeeEmail = 'employee@fomrahousing.in';

  static SupabaseClient get _client => Supabase.instance.client;

  LoginPortal? _portal;
  String? _loginEmail;
  String? _loginDisplayName;

  // ── "Access as User" (management impersonation) ────────────────────────────
  // While active, the app resolves currentUser/role/portal to the accessed
  // employee — so every permission, scope and screen behaves as that user —
  // while the REAL Supabase session stays management's. The banner and the
  // whole app react to [impersonation].
  EmployeeProfile? _impersonated;
  DateTime? _impersonationStart;

  /// Fires when access-as-user starts or ends, so the shell/banner rebuild.
  final ValueNotifier<EmployeeProfile?> impersonation = ValueNotifier(null);

  bool get isImpersonating => _impersonated != null;
  EmployeeProfile? get impersonatedUser => _impersonated;
  DateTime? get impersonationStart => _impersonationStart;

  /// Begin accessing the app as [user]. No-op if already impersonating (nested
  /// access is not allowed). The caller records the audit entry while still
  /// management, then calls this.
  void startImpersonation(EmployeeProfile user) {
    if (_impersonated != null) return;
    _impersonated = user;
    _impersonationStart = DateTime.now();
    impersonation.value = user;
  }

  /// Restore the original management session.
  void stopImpersonation() {
    if (_impersonated == null) return;
    _impersonated = null;
    _impersonationStart = null;
    impersonation.value = null;
  }

  LoginPortal? get loginPortal =>
      _impersonated != null ? LoginPortal.employee : _portal;

  bool get isManagement =>
      _impersonated == null && _portal == LoginPortal.management;
  bool get isEmployee =>
      _impersonated != null || _portal == LoginPortal.employee;

  static String emailForPortal(LoginPortal portal) => switch (portal) {
        LoginPortal.management => managementEmail,
        LoginPortal.employee => employeeEmail,
      };

  AppUser? get currentUser {
    // Accessing as another user: the whole app sees them, not management.
    final imp = _impersonated;
    if (imp != null) {
      return AppUser(
        id: imp.email,
        email: imp.email,
        fullName: imp.fullName,
        role: 'employee',
        createdAt: imp.joinedOn,
      );
    }
    final u = _client.auth.currentUser;
    if (u != null) {
      final email = u.email ?? _loginEmail ?? '';
      return AppUser(
        id: u.id,
        email: email,
        fullName: _loginDisplayName ??
            u.userMetadata?['full_name'] as String? ??
            _defaultNameForEmail(email),
        phone: u.userMetadata?['phone'] as String?,
        role: u.userMetadata?['role'] as String? ??
            (_portal == LoginPortal.management ? 'management' : 'employee'),
        createdAt: DateTime.parse(u.createdAt),
      );
    }
    if (_portal != null) {
      final email = _loginEmail ?? emailForPortal(_portal!);
      return AppUser(
        id: 'local-${_portal!.name}',
        email: email,
        fullName: _loginDisplayName ?? _defaultNameForEmail(email),
        role: _portal == LoginPortal.management ? 'management' : 'employee',
        createdAt: DateTime.now(),
      );
    }
    return null;
  }

  bool get isLoggedIn =>
      _client.auth.currentUser != null || _portal != null;

  /// True when the app holds a REAL Supabase Auth session — required for the
  /// locked-down (authenticated-only) database. False means the login fell back
  /// to local mode (anon), which the RLS lockdown would block from writing.
  bool get hasRealSession => _client.auth.currentUser != null;

  Future<void> restoreSession() async {
    final portalName = await tabGetString(_portalKey);
    _loginEmail = await tabGetString(_loginEmailKey);
    _loginDisplayName = await tabGetString(_loginNameKey);
    if (portalName == LoginPortal.management.name) {
      _portal = LoginPortal.management;
    } else if (portalName == LoginPortal.employee.name) {
      _portal = LoginPortal.employee;
    }

    final authEmail = _client.auth.currentUser?.email?.trim().toLowerCase();
    if (authEmail == managementEmail) {
      _portal = LoginPortal.management;
    } else if (authEmail == employeeEmail) {
      _portal = LoginPortal.employee;
    }

    final local = (await tabGetString(_localSessionKey)) == 'true';
    // Keep the session while the Supabase session is missing only if it's a
    // local login or we're still inside the post-login grace window. This stops
    // a reload from bouncing the user back to the login screen.
    if (!local &&
        !(await _withinLoginGrace()) &&
        _client.auth.currentUser == null) {
      _portal = null;
      _loginEmail = null;
      _loginDisplayName = null;
      await tabRemove(_portalKey);
      await tabRemove(_loginEmailKey);
      await tabRemove(_loginNameKey);
      await tabRemove(_loginAtKey);
    }
  }

  /// Whether the last login was recent enough to keep the session alive.
  Future<bool> _withinLoginGrace() async {
    final raw = await tabGetString(_loginAtKey);
    if (raw == null) return false;
    final at = DateTime.tryParse(raw);
    if (at == null) return false;
    return DateTime.now().difference(at) < _sessionGrace;
  }

  static String _defaultNameForEmail(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized == managementEmail) return 'Management';
    if (normalized == employeeEmail) return 'Employee';
    final local = email.split('@').first.trim();
    if (local.isEmpty) return 'User';
    return local[0].toUpperCase() + local.substring(1);
  }

  Future<String> _resolveDisplayName(String email, LoginPortal portal) async {
    final normalized = email.trim().toLowerCase();
    if (normalized == managementEmail) return 'Management';
    if (normalized == employeeEmail) return 'Employee';
    final profile = await EmployeeService.findByEmail(normalized);
    if (profile != null && profile.fullName.trim().isNotEmpty) {
      return profile.fullName.trim();
    }
    return _defaultNameForEmail(normalized);
  }

  Future<bool> checkSession() async {
    await restoreSession();
    if (_client.auth.currentUser != null) return true;
    if ((await tabGetString(_localSessionKey)) == 'true' && _portal != null) {
      return true;
    }
    return (await _withinLoginGrace()) && _portal != null;
  }

  Future<void> loginWithPortal(
    String email,
    String password,
    LoginPortal portal,
  ) async {
    final normalizedEmail = email.trim().toLowerCase();
    // Same real mobile-keyboard/autofill bug as login() below — a trailing
    // space on the password field breaks an otherwise-correct password.
    password = password.trim();

    if (portal == LoginPortal.management &&
        normalizedEmail != managementEmail) {
      throw const ApiException(
        statusCode: 401,
        message: 'Invalid email or password.',
      );
    }
    // No pre-login employee_profiles lookup here. That table is readable by
    // authenticated users only, so before sign-in the query returned nothing
    // and login failed with "Invalid email or password" for a correct
    // password — except on a device that happened to hold a cached employee
    // list from an earlier login. That is exactly why the same account worked
    // on one device and not another, and why Supabase's auth logs showed no
    // rejected attempt at all. Supabase checks the password first; the
    // employee's active status is checked right after, as an authenticated
    // query (see _ensureActiveEmployee).
    // Prefer a REAL Supabase Auth session — that's what makes locked-down
    // (authenticated-only) RLS work. If Supabase accepts the credentials we're
    // done; the password that logs you in is guaranteed to be the auth password.
    var supabaseOk = false;
    // Distinguish *why* sign-in failed instead of collapsing every case into
    // "Invalid email or password" — that masking previously took real
    // debugging time to see through (the Aug-24 sessionStorage bug looked
    // identical to a wrong password until server-side timestamps proved
    // otherwise). A network failure, a rate limit, and a genuinely wrong
    // password are different problems with different fixes; the person
    // typing the password deserves to know which one they're looking at.
    String? networkOrOtherDetail;
    var rateLimited = false;
    try {
      await _client.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
      supabaseOk = _client.auth.currentUser != null;
    } on AuthRetryableFetchException catch (e) {
      supabaseOk = false;
      networkOrOtherDetail = e.message;
    } on AuthApiException catch (e) {
      supabaseOk = false;
      final code = (e.code ?? '').toLowerCase();
      final msg = e.message.toLowerCase();
      if (code.contains('rate_limit') || msg.contains('rate limit')) {
        rateLimited = true;
      }
      // Anything else (e.g. actual invalid_credentials) falls through to
      // the standard "Invalid email or password" below — that part of the
      // original behavior was correct.
    } catch (e) {
      supabaseOk = false;
      networkOrOtherDetail = e.toString();
    }

    // Real Supabase Auth is the ONLY accepted credential now — there is no
    // default ('fomra@2024') or local-password fallback. Each account's
    // password is the one the user set (via their invite / a change).
    if (!supabaseOk) {
      if (networkOrOtherDetail != null || rateLimited) {
        debugPrint(
          '[auth] sign-in did not succeed for $normalizedEmail '
          '(network/other detail: $networkOrOtherDetail, rateLimited: $rateLimited)',
        );
      }
      if (networkOrOtherDetail != null) {
        throw ApiException(
          statusCode: 0,
          message:
              "Couldn't reach the server. Check your connection and try again.",
        );
      }
      if (rateLimited) {
        throw const ApiException(
          statusCode: 429,
          message: 'Too many attempts. Please wait a few minutes and try again.',
        );
      }
      throw const ApiException(
        statusCode: 401,
        message: 'Invalid email or password.',
      );
    }

    if (portal == LoginPortal.employee && normalizedEmail != employeeEmail) {
      await _ensureActiveEmployee(normalizedEmail);
    }

    _portal = portal;
    _loginEmail = normalizedEmail;
    _loginDisplayName = await _resolveDisplayName(normalizedEmail, portal);
    await tabSetString(_portalKey, portal.name);
    await tabSetString(_loginEmailKey, normalizedEmail);
    await tabSetString(_loginNameKey, _loginDisplayName!);
    await tabSetString(_localSessionKey, 'false');
    await tabSetString(_loginAtKey, DateTime.now().toIso8601String());
  }

  /// Post-sign-in gate for individual employee logins: a deactivated or
  /// removed employee must not get in even though their Supabase Auth
  /// password still works. Runs with the new session, so RLS allows the read.
  /// Only a definite answer blocks — if the lookup itself fails (network,
  /// table unavailable) the already-verified login is allowed through rather
  /// than turned into a misleading "wrong password".
  Future<void> _ensureActiveEmployee(String normalizedEmail) async {
    Map<String, dynamic>? row;
    try {
      row = await _client
          .from('employee_profiles')
          .select('status')
          .eq('email', normalizedEmail)
          .maybeSingle();
    } catch (e) {
      debugPrint('[auth] employee status check skipped: $e');
      return;
    }
    final status = (row?['status'] as String? ?? '').trim().toLowerCase();
    if (row != null && status == EmployeeStatus.active.name) return;
    try {
      await _client.auth.signOut();
    } catch (_) {}
    throw ApiException(
      statusCode: 403,
      message: row == null
          ? 'This login is not linked to an employee profile. '
              'Please contact your admin.'
          : 'Your account is inactive. Please contact your admin.',
    );
  }

  Future<void> login(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    // Real bug, not theoretical: mobile keyboards/autofill are prone to
    // appending a trailing space (tapping a suggestion, password-manager
    // autofill) in a way desktop physical keyboards rarely do — an
    // otherwise-correct password then fails because the extra character
    // is real to the auth check. The email field already normalizes for
    // exactly this class of issue; the password field never did.
    password = password.trim();

    // Every account other than the shared management login signs in through
    // the employee portal. No pre-login database lookup decides this — that
    // lookup is what made login depend on the device (see loginWithPortal).
    // A wrong email or password is rejected by Supabase itself, and an
    // inactive employee by the post-sign-in check.
    final portal = normalized == managementEmail
        ? LoginPortal.management
        : LoginPortal.employee;

    await loginWithPortal(email, password, portal);
  }

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String role = 'agent',
  }) async {
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          if (phone != null) 'phone': phone,
          'role': role,
        },
      );
      return true;
    } on AuthException catch (e) {
      throw ApiException(statusCode: 400, message: e.message);
    }
  }

  /// Sends a "reset your password" email to [email]. The link lands on the
  /// app's /set-password screen where the user chooses a new password. For
  /// privacy, Supabase does not reveal whether the address has an account.
  Future<void> sendPasswordReset(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('@')) {
      throw const ApiException(
        statusCode: 400,
        message: 'Enter a valid email address.',
      );
    }
    String redirect;
    try {
      final origin = Uri.base.origin; // real web origin (dev or prod)
      redirect = origin.startsWith('http')
          ? '$origin/set-password'
          : 'https://fomra-ls.vercel.app/set-password';
    } catch (_) {
      redirect = 'https://fomra-ls.vercel.app/set-password';
    }
    try {
      await _client.auth.resetPasswordForEmail(normalized, redirectTo: redirect);
    } on AuthException catch (e) {
      throw ApiException(statusCode: 400, message: e.message);
    }
  }

  Future<void> logout() async {
    stopImpersonation();
    try {
      await _client.auth.signOut();
    } catch (_) {}
    _portal = null;
    _loginEmail = null;
    _loginDisplayName = null;
    await tabRemove(_portalKey);
    await tabRemove(_localSessionKey);
    await tabRemove(_loginEmailKey);
    await tabRemove(_loginNameKey);
    await tabRemove(_loginAtKey);
  }

  /// Changes the password for the currently signed-in Supabase account.
  /// The current password is verified by re-authenticating; the new one is then
  /// saved to Supabase Auth (the single source of truth — no local fallback).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _client.auth.currentUser;
    final email = (user?.email ?? _loginEmail)?.trim().toLowerCase();
    if (user == null || email == null || email.isEmpty) {
      throw const ApiException(
        statusCode: 401,
        message: 'You are not signed in.',
      );
    }
    final newTrimmed = newPassword.trim();
    if (newTrimmed.length < 8) {
      throw const ApiException(
        statusCode: 400,
        message: 'New password must be at least 8 characters.',
      );
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(newTrimmed) ||
        !RegExp(r'\d').hasMatch(newTrimmed)) {
      throw const ApiException(
        statusCode: 400,
        message: 'New password must include at least one letter and one number.',
      );
    }

    // Verify the current password by re-authenticating.
    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: currentPassword.trim(),
      );
    } on AuthException {
      throw const ApiException(
        statusCode: 400,
        message: 'Current password is incorrect.',
      );
    }

    try {
      await _client.auth.updateUser(UserAttributes(password: newTrimmed));
    } on AuthException catch (e) {
      throw ApiException(statusCode: 400, message: e.message);
    }
  }

  String routeForPortal(LoginPortal portal) => '/home';

  String? get postLoginRoute =>
      _portal != null ? routeForPortal(_portal!) : null;
}
