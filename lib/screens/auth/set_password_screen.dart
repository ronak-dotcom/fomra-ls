import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_link.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';

/// Landing screen for the "set your password" link in an invite email.
///
/// The invite link redirects here with the auth tokens in the URL. We exchange
/// them for a session ([getSessionFromUrl]), let the invited user choose a
/// password, save it via [updateUser], then send them to the login screen.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _verifying = true;
  bool _saving = false;
  bool _obscure = true;
  String? _linkError;
  String? _email;

  @override
  void initState() {
    super.initState();
    _consumeLink();
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Turn the tokens in the invite URL into an authenticated session.
  Future<void> _consumeLink() async {
    try {
      final res = await Supabase.instance.client.auth
          .getSessionFromUrl(AuthLink.initialUri);
      _email = res.session.user.email;
    } catch (_) {
      _linkError =
          'This invitation link is invalid or has expired. Ask management to send a new one.';
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  String? _validatePassword(String? v) {
    final p = (v ?? '').trim();
    if (p.length < 8) return 'At least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
      return 'Include at least one letter and one number.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pwCtrl.text.trim() != _confirmCtrl.text.trim()) {
      AppFeedback.error(context, 'Passwords do not match.');
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _pwCtrl.text.trim()),
      );
      // Sign out so they log in fresh with the password they just chose.
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      AppFeedback.success(context, 'Password set. Please log in.');
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context,
          'Could not set password: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.fomraPageBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _verifying
                ? const _Busy(label: 'Verifying your invitation…')
                : _linkError != null
                    ? _LinkError(message: _linkError!)
                    : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      radius: 16,
      interactive: false,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded,
                size: 40, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              'Set your password',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.fomraTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _email == null
                  ? 'Choose a password to finish setting up your account.'
                  : 'Choose a password for $_email.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.fomraTextSecondary),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _pwCtrl,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              // Corrupting a character here is worse than at login: the
              // person would silently set a different password than what
              // they typed and see it "confirmed" successfully (both
              // fields get corrupted identically), then be locked out the
              // moment they retype it correctly anywhere else. See
              // login_screen.dart's password field for the full mechanism.
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              keyboardType: TextInputType.visiblePassword,
              validator: _validatePassword,
              decoration: InputDecoration(
                labelText: 'New password',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              keyboardType: TextInputType.visiblePassword,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'At least 8 characters, including a letter and a number.',
              style: TextStyle(fontSize: 11.5, color: context.fomraTextTertiary),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: _saving ? 'Saving…' : 'Set password & continue',
              icon: Icons.check_rounded,
              loading: _saving,
              expand: true,
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  final String label;
  const _Busy({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(height: 16),
        Text(label, style: TextStyle(color: context.fomraTextSecondary)),
      ],
    );
  }
}

class _LinkError extends StatelessWidget {
  final String message;
  const _LinkError({required this.message});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      radius: 16,
      interactive: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off_rounded, size: 40, color: AppColors.error),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.fomraTextSecondary)),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Go to login',
            expand: true,
            onPressed: () => Navigator.of(context)
                .pushNamedAndRemoveUntil('/login', (_) => false),
          ),
        ],
      ),
    );
  }
}
