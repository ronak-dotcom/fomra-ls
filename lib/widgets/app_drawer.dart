import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import 'ui/profile_avatar.dart';

class _MenuItem {
  final String title;
  final IconData icon;
  final String route;

  const _MenuItem(this.title, this.icon, this.route);
}

/// The mobile hamburger menu: Home, Workspace, Reports, Settings.
const _menuItems = [
  _MenuItem('Home', Icons.home_outlined, '/home'),
  _MenuItem('Land Workspace', Icons.space_dashboard_outlined, '/land-lead'),
  _MenuItem('Reports', Icons.assessment_outlined, '/reports'),
  _MenuItem('Settings', Icons.settings_outlined, '/settings'),
];

/// Same blue rail gradient as the web side nav, so the mobile menu matches.
const _drawerGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
);

class AppDrawer extends StatelessWidget {
  final String currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    const menuItems = _menuItems;
    final isDark = context.isDarkMode;

    return Drawer(
      // Blue rail (light) / sidebar surface (dark) — no white flash behind the
      // gradient — so the white icons read the same as the web side nav.
      backgroundColor: isDark ? context.fomraSidebarBg : AppColors.ink,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: isDark ? null : _drawerGradient),
        child: Column(
          children: [
            _DrawerHeader(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final item = menuItems[index];
                  final isActive = currentRoute == item.route ||
                      (item.route == '/land-lead' &&
                          currentRoute == '/task-management');
                  return _DrawerTile(item: item, isActive: isActive);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 52, 20, 18),
          decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  colors: [
                    Color(0xFF152A52),
                    Color(0xFF1E293B),
                    Color(0xFF2A2258),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isDark ? null : AppColors.primaryDark,
          border: isDark
              ? Border(bottom: BorderSide(color: context.fomraBorder))
              : null,
          ),
          // Just the account row — the app header already shows the brand, so
          // the drawer skips the logo/name block.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProfileAvatar(
                    email: AuthService.instance.currentUser?.email,
                    name: AuthService.instance.currentUser?.fullName ?? 'User',
                    radius: 18,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AuthService.instance.isManagement
                              ? 'Management'
                              : (AuthService.instance.currentUser?.fullName ??
                                  'User'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? context.fomraTextPrimary : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          AuthService.instance.isManagement
                              ? 'Administrator'
                              : 'Employee',
                          style: TextStyle(
                            color: isDark
                                ? context.fomraTextSecondary
                                : const Color(0xFFB0BEC5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final _MenuItem item;
  final bool isActive;

  const _DrawerTile({required this.item, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    // Mirror the web side nav: white icons on the blue rail, and the active
    // item as a white rounded box with a brand-blue icon.
    final Color iconBg;
    final Color iconColor;
    List<BoxShadow>? iconShadow;
    if (isDark) {
      iconBg =
          isActive ? AppColors.primary.withValues(alpha: 0.18) : Colors.transparent;
      iconColor = isActive
          ? AppColors.primaryLight
          : AppColors.darkTextSecondary.withValues(alpha: 0.85);
    } else {
      iconBg = isActive ? Colors.white : Colors.transparent;
      iconColor = isActive ? AppColors.primary : Colors.white.withValues(alpha: 0.82);
      iconShadow = isActive
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ]
          : null;
    }

    final textColor = isDark
        ? (isActive
            ? AppColors.darkTextPrimary
            : AppColors.darkTextSecondary.withValues(alpha: 0.9))
        : Colors.white.withValues(alpha: isActive ? 1.0 : 0.88);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? (isDark
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.12))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(9),
            boxShadow: iconShadow,
          ),
          child: Icon(
            item.icon,
            color: iconColor,
            size: 18,
          ),
        ),
        title: Text(
          item.title,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onTap: () {
          Navigator.pop(context);
          if (!isActive) {
            Navigator.pushReplacementNamed(context, item.route);
          }
        },
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

