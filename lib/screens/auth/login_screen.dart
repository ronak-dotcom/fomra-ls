import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/push_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_input.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_feedback.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.instance.login(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
      if (!mounted) return;
      // Ask for push permission now, still inside the login tap's user gesture,
      // so the browser shows a real prompt (not the suppressed quiet UI). Once
      // granted per browser profile, it never asks again.
      PushService.promptAndSync();
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException
            ? e.message
            : 'Invalid email or password. Please try again.';
      });
    }
  }

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final formKey = GlobalKey<FormState>();
    var sending = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reset password'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Enter your account email and we'll send a link to set a new password.",
                  style: TextStyle(
                      fontSize: 13, color: context.fomraTextSecondary),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: emailCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setLocal(() => sending = true);
                      try {
                        await AuthService.instance
                            .sendPasswordReset(emailCtrl.text);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        AppFeedback.success(context,
                            'If that email has an account, a reset link is on its way.');
                      } catch (e) {
                        setLocal(() => sending = false);
                        if (!ctx.mounted) return;
                        AppFeedback.error(
                            ctx,
                            e is ApiException
                                ? e.message
                                : 'Could not send reset email.');
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send link'),
            ),
          ],
        ),
      ),
    );
    emailCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = FomraLayout.isDesktop(context);

    return Scaffold(
      body: wide ? _buildSplitLayout(context) : _buildMobileLayout(context),
    );
  }

  Widget _buildSplitLayout(BuildContext context) {
    return Row(
      children: [
        // Left: blue background with brand text.
        Expanded(
          flex: 5,
          child: Stack(
            children: [
              Container(
                // Same gradient as the in-app header, so the login panel matches
                // the app's look (dark navy in dark mode).
                decoration: BoxDecoration(gradient: context.fomraHeroGradient),
              ),
              Positioned(
                top: -120,
                left: -80,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                right: -140,
                bottom: -160,
                child: Container(
                  width: 420,
                  height: 420,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Text(
                              'Fomra Housing and Infrastructure',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Fomra LandIQ',
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 64,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.1,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Land intelligence and workflow platform\nfor enterprise real estate teams.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 16,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Right: sign-in form panel. Dark-mode uses the page background so the
        // dark form card doesn't sit on a jarring white panel.
        Expanded(
          flex: 4,
          child: ColoredBox(
            color: context.isDarkMode ? context.fomraPageBg : Colors.white,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _buildFormCard(context, showBranding: false),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final isDark = context.isDarkMode;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [
                  AppColors.darkBackground,
                  Color(0xFF0F2447),
                  Color(0xFF152A52),
                ]
              : const [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: FomraLayout.responsiveClamp(
                  context,
                  min: 20,
                  max: 28,
                ),
                vertical: 24,
              ),
            child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width >= 600 ? 400 : 360,
                ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Fomra LandIQ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fomra Housing',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 36),
                  _buildFormCard(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard(BuildContext context, {bool showBranding = true}) {
    final isDark = context.isDarkMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? context.fomraSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.fomraBorder),
        boxShadow: isDark
            ? context.fomraCardShadow
            : AppColors.elevatedShadow,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!showBranding) ...[
              Text(
                'Sign in',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: context.fomraTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Use your Fomra Housing account',
                style: TextStyle(
                  fontSize: 14,
                  color: context.fomraTextSecondary,
                ),
              ),
              const SizedBox(height: 24),
            ],
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Email is required' : null,
              decoration: FomraInput.decoration(
                context: context,
                label: 'Email',
                icon: Icons.email_outlined,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              // Confirmed root cause of a real, hard-to-diagnose login
              // failure: some mobile keyboards (Samsung Keyboard observed)
              // silently replace straight quotes/dashes with "smart" curly
              // variants as you type, even in an obscured field, since
              // Flutter doesn't disable this just because obscureText is
              // true — it's a separate setting. Whatever gets typed must
              // reach the server byte-for-byte.
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _login(),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Password is required' : null,
              decoration: FomraInput.decoration(
                context: context,
                label: 'Password',
                icon: Icons.lock_outline,
              ).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: context.fomraTextSecondary,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading ? null : _forgotPassword,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppColors.coloredShadow(AppColors.primary),
                ),
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vector recreation of the FOMRA Housing & Infrastructure logo.
/// Used as a fallback until `assets/images/fomra_logo.png` is added.
class FomraLogo extends StatelessWidget {
  final double width;
  const FomraLogo({super.key, this.width = 380});

  static const Color _ink = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'FOMRA',
                style: TextStyle(
                  fontSize: width * 0.215,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                  letterSpacing: -width * 0.006,
                  height: 1,
                ),
              ),
              SizedBox(width: width * 0.02),
              CustomPaint(
                size: Size(width * 0.20, width * 0.185),
                painter: _SwooshPainter(),
              ),
            ],
          ),
          SizedBox(height: width * 0.028),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'HOUSING & INFRASTRUCTURE PVT. LTD.',
              style: TextStyle(
                fontSize: width * 0.053,
                fontWeight: FontWeight.w700,
                color: _ink,
                letterSpacing: width * 0.004,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwooshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xFF0E1E52), Color(0xFF2E6BD6)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    // Main swoosh: a bold wing — pointed tail at lower-left,
    // wide blunt blade at upper-right.
    final blade = Path()
      ..moveTo(w * 0.04, h * 0.70)
      // top edge sweeping up to the right tip
      ..quadraticBezierTo(w * 0.56, h * 0.50, w * 1.00, h * 0.02)
      // blunt right end
      ..quadraticBezierTo(w * 1.00, h * 0.18, w * 0.98, h * 0.30)
      // bottom edge curving back to the tail point
      ..quadraticBezierTo(w * 0.54, h * 0.66, w * 0.04, h * 0.70)
      ..close();
    canvas.drawPath(blade, paint);

    // Slim accent stroke beneath, echoing the logo's double sweep.
    final accent = Path()
      ..moveTo(w * 0.16, h * 0.94)
      ..quadraticBezierTo(w * 0.58, h * 0.66, w * 0.94, h * 0.42)
      ..quadraticBezierTo(w * 0.62, h * 0.78, w * 0.24, h * 1.00)
      ..close();
    canvas.drawPath(accent, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
