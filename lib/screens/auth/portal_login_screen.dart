import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_input.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';

class PortalLoginScreen extends StatefulWidget {
  const PortalLoginScreen({super.key, required this.portal});

  final LoginPortal portal;

  @override
  State<PortalLoginScreen> createState() => _PortalLoginScreenState();
}

class _PortalLoginScreenState extends State<PortalLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  bool get _isManagement => widget.portal == LoginPortal.management;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = AuthService.emailForPortal(widget.portal);
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.instance.loginWithPortal(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
        widget.portal,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AuthService.instance.routeForPortal(widget.portal),
      );
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

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Scaffold(
      body: Container(
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
          child: Column(
            children: [
              // Back button row
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),

              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1.5),
                          ),
                          child: Icon(
                            _isManagement
                                ? Icons.admin_panel_settings_outlined
                                : Icons.badge_outlined,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isManagement
                              ? 'Management Portal'
                              : 'Employee Portal',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: FomraLayout.responsiveClamp(
                              context,
                              min: 22,
                              max: 26,
                            ),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Fomra LandIQ · Fomra Housing',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Login card
                        Container(
                          padding: EdgeInsets.all(
                            FomraLayout.responsiveClamp(
                              context,
                              min: 18,
                              max: 24,
                            ),
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? context.fomraSurface : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: isDark
                                ? Border.all(color: context.fomraBorder)
                                : null,
                            boxShadow: isDark
                                ? context.fomraCardShadow
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: context.fomraTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Full access to land workspace & market intel',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: context.fomraTextSecondary),
                                ),
                                const SizedBox(height: 22),

                                // Email
                                TextFormField(
                                  controller: _emailCtrl,
                                  readOnly: true,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: FomraInput.decoration(
                                    context: context,
                                    label: 'Email Address',
                                    icon: Icons.email_outlined,
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Password
                                TextFormField(
                                  controller: _passwordCtrl,
                                  obscureText: _obscure,
                                  // See login_screen.dart's password field
                                  // for why: a mobile keyboard silently
                                  // altering a character here caused a real,
                                  // hard-to-diagnose login failure.
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  smartDashesType: SmartDashesType.disabled,
                                  smartQuotesType: SmartQuotesType.disabled,
                                  keyboardType: TextInputType.visiblePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _login(),
                                  validator: (v) =>
                                      (v == null || v.isEmpty)
                                          ? 'Password is required'
                                          : null,
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
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                    ),
                                  ),
                                ),

                                // Error
                                if (_error != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.error
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: AppColors.error
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Row(children: [
                                      const Icon(Icons.error_outline,
                                          size: 15, color: AppColors.error),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_error!,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.error)),
                                      ),
                                    ]),
                                  ),
                                ],

                                const SizedBox(height: 22),

                                // Sign in button
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isDark
                                          ? AppColors.primaryLight
                                          : AppColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      elevation: 0,
                                    ),
                                    child: _loading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5),
                                          )
                                        : Text(
                                            _isManagement
                                                ? 'Management Sign In'
                                                : 'Employee Sign In',
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 13,
                                  color: Colors.white.withValues(alpha: 0.6)),
                              const SizedBox(width: 6),
                              Text(
                                'Secured · Fomra Housing Pvt. Ltd.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.6)),
                              ),
                            ]),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
