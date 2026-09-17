import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/land_lead.dart';
import '../models/land_lead_signed_request.dart';
import '../models/land_lead_site_visit.dart';
import '../models/lead_list_filter.dart';
import '../models/monthly_target_submission.dart';
import '../services/lead_drop_approval_service.dart';
import '../services/app_store.dart';
import '../services/profile_photo_service.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_layout.dart';
import '../theme/fomra_theme_context.dart';
import 'ui/app_components.dart';
import 'ui/profile_avatar.dart';

/// Full date for the home hero — e.g. Monday, 6 July 2026.
String portalHomeDateLabel(DateTime date) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
}

bool portalIsSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Display name for greeting — management portal uses "Management".
String portalHomeDisplayName({
  required String fullName,
  required bool isManagement,
}) {
  if (isManagement) return 'Management';
  final first = fullName.trim().split(RegExp(r'\s+')).firstWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
  return first.isEmpty ? 'User' : first;
}

/// Time-of-day greeting per product brief.
String portalTimeGreeting(DateTime now, String displayName) {
  final hour = now.hour;
  final salutation = switch (hour) {
    >= 5 && < 12 => 'Happy Morning',
    >= 12 && < 17 => 'Happy Afternoon',
    _ => 'Happy Evening',
  };
  return '$salutation, $displayName!👋';
}

/// Staggered fade-in for home sections (150–250ms).
class PortalFadeSection extends StatefulWidget {
  final Widget child;
  final int index;

  const PortalFadeSection({
    super.key,
    required this.child,
    this.index = 0,
  });

  @override
  State<PortalFadeSection> createState() => _PortalFadeSectionState();
}

class _PortalFadeSectionState extends State<PortalFadeSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _c, curve: AppMotion.curve);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: AppMotion.curve));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class PortalWelcomeHeader extends StatelessWidget {
  final String greeting;
  final String dateLabel;
  final int totalLeads;
  final int activeLeads;
  final ValueChanged<LeadListFilter>? onSummaryTap;

  /// Configurable third KPI tile. Management uses "Approval pending" (opening
  /// the approvals list); employees use "Owner meeting pending".
  final String thirdLabel;
  final int thirdValue;
  final IconData thirdIcon;
  final VoidCallback? onThirdTap;

  const PortalWelcomeHeader({
    super.key,
    required this.greeting,
    required this.dateLabel,
    required this.totalLeads,
    required this.activeLeads,
    required this.thirdLabel,
    required this.thirdValue,
    required this.thirdIcon,
    this.onThirdTap,
    this.onSummaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: AppColors.radiusLg,
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: AppMotion.slow,
                      switchInCurve: AppMotion.curve,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                      child: Text(
                        greeting,
                        key: ValueKey(greeting),
                        // Slightly smaller greeting on phones.
                        style: (FomraLayout.isMobile(context)
                                ? Theme.of(context).textTheme.titleLarge
                                : Theme.of(context).textTheme.headlineSmall)
                            ?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: context.fomraTextPrimary,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              // Mobile: three compact square tiles in one row (better use of the
              // width than full-width stacked rows). Wider screens keep the roomy
              // horizontal tiles.
              final square = constraints.maxWidth < 640;
              final tiles = [
                PortalSummaryTile(
                  label: 'Total sites',
                  value: totalLeads,
                  icon: Icons.location_on_outlined,
                  accent: AppColors.primary,
                  compact: square,
                  onTap: onSummaryTap == null
                      ? null
                      : () => onSummaryTap!(LeadListFilter.totalLeads),
                ),
                PortalSummaryTile(
                  label: 'Active sites',
                  value: activeLeads,
                  icon: Icons.trending_up_rounded,
                  accent: AppColors.success,
                  compact: square,
                  onTap: onSummaryTap == null
                      ? null
                      : () => onSummaryTap!(LeadListFilter.activeLeads),
                ),
                PortalSummaryTile(
                  label: thirdLabel,
                  value: thirdValue,
                  icon: thirdIcon,
                  accent: AppColors.warning,
                  compact: square,
                  onTap: onThirdTap,
                ),
              ];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    Expanded(
                      child: square
                          ? AspectRatio(aspectRatio: 1, child: tiles[i])
                          : tiles[i],
                    ),
                    if (i < tiles.length - 1)
                      const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class PortalSummaryTile extends StatefulWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  /// Compact square layout (icon stacked over value + label) for the mobile
  /// three-in-a-row summary. Default false = the roomy horizontal tile.
  final bool compact;

  const PortalSummaryTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
    this.compact = false,
  });

  @override
  State<PortalSummaryTile> createState() => _PortalSummaryTileState();
}

class _PortalSummaryTileState extends State<PortalSummaryTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: AppMotion.normal,
        curve: AppMotion.curve,
        transform: _hovered
            ? Matrix4.translationValues(0, -2, 0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: widget.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          border: Border.all(
            color: widget.accent.withValues(alpha: _hovered ? 0.28 : 0.14),
          ),
          boxShadow: _hovered ? context.fomraCardShadow : null,
        ),
        padding: widget.compact
            ? const EdgeInsets.all(9)
            : const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
        child: widget.compact ? _compactBody(context) : _wideBody(context),
      ),
    );

    if (widget.onTap == null) return tile;
    return GestureDetector(onTap: widget.onTap, child: tile);
  }

  Widget _iconChip({double box = 40, double glyph = AppIconSize.small}) {
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: context.fomraSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(widget.icon, color: widget.accent, size: glyph),
    );
  }

  /// Roomy horizontal tile — icon beside the value + label.
  Widget _wideBody(BuildContext context) {
    return Row(
      children: [
        _iconChip(),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedCounter(
                value: widget.value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: context.fomraTextPrimary,
                  height: 1.1,
                ),
              ),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.fomraTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Compact square tile — icon on top, value + label stacked below.
  Widget _compactBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _iconChip(box: 30, glyph: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedCounter(
              value: widget.value,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: context.fomraTextPrimary,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.12,
                fontWeight: FontWeight.w500,
                color: context.fomraTextSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class PortalQuickAction {
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const PortalQuickAction({
    required this.label,
    this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
}

/// A floating "Quick actions" button for the mobile home — tapping it opens a
/// bottom sheet listing the same actions the desktop Quick actions card shows,
/// so the card itself can be dropped on phones to reclaim the space.
class PortalQuickActionsFab extends StatelessWidget {
  final List<PortalQuickAction> actions;

  const PortalQuickActionsFab({super.key, required this.actions});

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.fomraSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ctx.fomraBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Quick actions',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ctx.fomraTextPrimary,
                  ),
                ),
              ),
            ),
            for (final a in actions)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: a.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(a.icon, color: a.accent, size: 20),
                ),
                title: Text(
                  a.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ctx.fomraTextPrimary,
                  ),
                ),
                subtitle: a.subtitle == null ? null : Text(a.subtitle!),
                onTap: () {
                  Navigator.pop(ctx);
                  a.onTap();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _open(context),
      // A warm amber — clearly apart from the blue/purple primary buttons
      // (Add Lead FAB, lead action FAB).
      backgroundColor: const Color(0xFFF59E0B),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.flash_on_rounded),
      label: const Text(
        'Quick actions',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class PortalQuickActionsGrid extends StatelessWidget {
  final List<PortalQuickAction> actions;

  /// When set, forces this many cards per row (e.g. `2` for a 2×2 panel).
  /// When null, desktop packs as many as fit; mobile stays 2-up.
  final int? columns;

  const PortalQuickActionsGrid({
    super.key,
    required this.actions,
    this.columns,
  });

  static const _cardWidth = 272.0;
  static const _cardHeight = 92.0;
  static const _gridGap = 16.0;

  @override
  Widget build(BuildContext context) {
    final forcedCols = columns;
    // Mobile web, or an explicit column count (side-by-side home panel): a
    // fixed N-per-row grid instead of a horizontally packing strip.
    if (forcedCols != null || FomraLayout.isMobile(context)) {
      const gap = 12.0;
      final perRow = forcedCols ?? 2;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: LayoutBuilder(
          builder: (context, c) {
            final cardW = c.maxWidth.isFinite
                ? (c.maxWidth - gap * (perRow - 1)) / perRow
                : _cardWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: cardW,
                    // Stacked icon + label needs a bit more height in a grid.
                    height: forcedCols != null ? 100 : 112,
                    child: _QuickActionCard(data: action),
                  ),
              ],
            );
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Fit as many cards per row as the min card width allows, then widen
          // each computed card so the row fills the full width (no trailing gap).
          // Uses a Wrap with explicit widths — never Expanded — so an unbounded
          // width constraint can't crash the layout (which blanked the page).
          final maxW = constraints.maxWidth;
          if (!maxW.isFinite || maxW <= 0) {
            return Wrap(
              spacing: _gridGap,
              runSpacing: _gridGap,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: _cardWidth,
                    height: _cardHeight,
                    child: _QuickActionCard(data: action),
                  ),
              ],
            );
          }
          var perRow = ((maxW + _gridGap) / (_cardWidth + _gridGap)).floor();
          if (perRow < 1) perRow = 1;
          if (perRow > actions.length) perRow = actions.length;
          final cardW = (maxW - _gridGap * (perRow - 1)) / perRow;

          return Wrap(
            spacing: _gridGap,
            runSpacing: _gridGap,
            children: [
              for (final action in actions)
                SizedBox(
                  width: cardW,
                  height: _cardHeight,
                  child: _QuickActionCard(data: action),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickActionCard extends StatefulWidget {
  final PortalQuickAction data;

  const _QuickActionCard({required this.data});

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _hovered = false;

  static const _motion = Duration(milliseconds: 190);
  static const _curve = Curves.easeInOut;

  PortalQuickAction get data => widget.data;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final cardColor = isDark
        ? context.fomraSurface.withValues(alpha: 0.88)
        : context.fomraSurface;
    final borderColor = _hovered && isDark
        ? AppColors.primary.withValues(alpha: 0.55)
        : context.fomraBorder;
    final iconTint = data.accent.withValues(alpha: _hovered ? 0.18 : 0.12);
    final shadowAlpha = isDark
        ? (_hovered ? 0.42 : 0.28)
        : (_hovered ? 0.12 : 0.08);
    final shadowBlur = _hovered ? 28.0 : 20.0;
    final shadowOffset = _hovered ? 10.0 : 6.0;

    final mobile = FomraLayout.isMobile(context);

    final iconBox = AnimatedScale(
      scale: _hovered ? 1.05 : 1,
      duration: _motion,
      curve: _curve,
      child: AnimatedContainer(
        duration: _motion,
        curve: _curve,
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: iconTint,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Icon(data.icon, size: 21, color: data.accent),
      ),
    );

    // Mobile: icon on top, wrapping label beneath — so the full label shows
    // instead of truncating ("Sho…"). Tablet/desktop keep the icon + label row.
    final Widget content = mobile
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconBox,
              const SizedBox(height: 8),
              Text(
                data.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: context.fomraTextPrimary,
                ),
              ),
            ],
          )
        : Row(
            children: [
              iconBox,
              const SizedBox(width: 24),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    height: 1.2,
                    color: context.fomraTextPrimary,
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: _hovered ? 1 : 0,
                duration: _motion,
                curve: _curve,
                child: AnimatedSlide(
                  duration: _motion,
                  curve: _curve,
                  offset: _hovered ? Offset.zero : const Offset(-0.2, 0),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: _hovered && isDark
                        ? AppColors.primary
                        : context.fomraTextSecondary.withValues(
                            alpha: _hovered ? 0.9 : 0,
                          ),
                  ),
                ),
              ),
            ],
          );

    final card = AnimatedContainer(
      duration: _motion,
      curve: _curve,
      transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: _hovered && isDark ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (_hovered && isDark
                    ? AppColors.primary
                    : const Color(0xFF0F172A))
                .withValues(alpha: shadowAlpha),
            blurRadius: shadowBlur,
            offset: Offset(0, shadowOffset),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 20, vertical: 10),
      child: content,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: data.onTap,
        behavior: HitTestBehavior.opaque,
        child: isDark
            ? ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: card,
                ),
              )
            : card,
      ),
    );
  }
}

String _portalFormatVisitDateTime(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  return '${months[d.month - 1]} ${d.day}, ${d.year} · $hour:$minute $ampm';
}

class PortalApprovalsSection extends StatelessWidget {
  final List<LandLeadSiteVisit> visits;
  final List<LandLeadSignedRequest> signedRequests;
  final List<LeadDropApprovalRequest> dropRequests;
  final List<MonthlyTargetSubmission> monthlyTargets;
  final List<LandLead> leads;
  final bool loading;
  final Future<void> Function(LandLeadSiteVisit visit) onReview;
  final Future<void> Function(LandLeadSiteVisit visit) onApprove;
  final Future<void> Function(LandLeadSiteVisit visit) onReject;
  final Future<void> Function(LandLeadSignedRequest request)? onApproveSigned;
  final Future<void> Function(LandLeadSignedRequest request)? onRejectSigned;
  final Future<void> Function(LeadDropApprovalRequest request)? onApproveDrop;
  final Future<void> Function(LeadDropApprovalRequest request)? onRejectDrop;
  final Future<void> Function(MonthlyTargetSubmission submission)?
      onApproveMonthlyTarget;
  final Future<void> Function(MonthlyTargetSubmission submission)?
      onRejectMonthlyTarget;
  final Future<void> Function(MonthlyTargetSubmission submission)?
      onEditMonthlyTarget;

  const PortalApprovalsSection({
    super.key,
    required this.visits,
    this.signedRequests = const [],
    this.dropRequests = const [],
    this.monthlyTargets = const [],
    required this.leads,
    required this.loading,
    required this.onReview,
    required this.onApprove,
    required this.onReject,
    this.onApproveSigned,
    this.onRejectSigned,
    this.onApproveDrop,
    this.onRejectDrop,
    this.onApproveMonthlyTarget,
    this.onRejectMonthlyTarget,
    this.onEditMonthlyTarget,
  });

  LandLead? _leadFor(String leadId) {
    for (final l in leads) {
      if (l.leadId == leadId) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final empty = visits.isEmpty &&
        signedRequests.isEmpty &&
        dropRequests.isEmpty &&
        monthlyTargets.isEmpty;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppColors.radiusLg,
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Approvals',
            subtitle:
                'Pending site visit, project signed, drop, and monthly target requests',
            icon: Icons.verified_outlined,
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (empty)
            const PortalEmptyHint(
              hint: 'No pending approvals — new requests will appear here.',
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < visits.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        _ApprovalVisitRow(
                          visit: visits[i],
                          lead: _leadFor(visits[i].leadId),
                          onReview: () => onReview(visits[i]),
                          onApprove: () => onApprove(visits[i]),
                          onReject: () => onReject(visits[i]),
                        ),
                      ],
                      for (var i = 0; i < signedRequests.length; i++) ...[
                        if (i > 0 || visits.isNotEmpty)
                          const SizedBox(height: 6),
                        _ApprovalSignedRow(
                          request: signedRequests[i],
                          lead: _leadFor(signedRequests[i].leadId),
                          onApprove: onApproveSigned == null
                              ? null
                              : () => onApproveSigned!(signedRequests[i]),
                          onReject: onRejectSigned == null
                              ? null
                              : () => onRejectSigned!(signedRequests[i]),
                        ),
                      ],
                      for (var i = 0; i < dropRequests.length; i++) ...[
                        if (i > 0 ||
                            visits.isNotEmpty ||
                            signedRequests.isNotEmpty)
                          const SizedBox(height: 6),
                        _ApprovalDropRow(
                          request: dropRequests[i],
                          lead: _leadFor(dropRequests[i].leadId),
                          onApprove: onApproveDrop == null
                              ? null
                              : () => onApproveDrop!(dropRequests[i]),
                          onReject: onRejectDrop == null
                              ? null
                              : () => onRejectDrop!(dropRequests[i]),
                        ),
                      ],
                      for (var i = 0; i < monthlyTargets.length; i++) ...[
                        if (i > 0 ||
                            visits.isNotEmpty ||
                            signedRequests.isNotEmpty ||
                            dropRequests.isNotEmpty)
                          const SizedBox(height: 6),
                        _ApprovalMonthlyTargetRow(
                          submission: monthlyTargets[i],
                          onApprove: onApproveMonthlyTarget == null
                              ? null
                              : () =>
                                  onApproveMonthlyTarget!(monthlyTargets[i]),
                          onReject: onRejectMonthlyTarget == null
                              ? null
                              : () =>
                                  onRejectMonthlyTarget!(monthlyTargets[i]),
                          onEdit: onEditMonthlyTarget == null
                              ? null
                              : () => onEditMonthlyTarget!(monthlyTargets[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ApprovalMonthlyTargetRow extends StatefulWidget {
  final MonthlyTargetSubmission submission;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;
  final Future<void> Function()? onEdit;

  const _ApprovalMonthlyTargetRow({
    required this.submission,
    required this.onApprove,
    required this.onReject,
    required this.onEdit,
  });

  @override
  State<_ApprovalMonthlyTargetRow> createState() =>
      _ApprovalMonthlyTargetRowState();
}

class _ApprovalMonthlyTargetRowState extends State<_ApprovalMonthlyTargetRow> {
  bool _busy = false;

  Future<void> _act(Future<void> Function()? fn) async {
    if (fn == null || _busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _valuesSummary(Map<String, int> values) {
    final parts = [
      for (final c in TargetCategory.values)
        if (values.containsKey(c.key)) '${c.label} ${values[c.key]}',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.submission;
    final name =
        s.employeeName.isEmpty ? s.employeeEmail : s.employeeName;
    final meta = [
      if (s.employeeCode.isNotEmpty) 'ID ${s.employeeCode}',
      if (s.department.isNotEmpty) s.department,
      if (s.designation.isNotEmpty) s.designation,
      s.monthLabel,
      'Submitted ${s.submittedAt.day}/${s.submittedAt.month}/${s.submittedAt.year}',
    ].join(' · ');
    final values = s.approvedValues ?? s.submittedValues;
    final statusColor = s.status.color;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.flag_outlined, color: statusColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  s.status.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _valuesSummary(values),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: context.fomraTextSecondary,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, c) {
            final edit = OutlinedButton(
              onPressed: _busy ? null : () => _act(widget.onEdit),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: const Text('Edit Targets'),
            );
            final reject = OutlinedButton(
              onPressed: _busy ? null : () => _act(widget.onReject),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: const Text('Reject'),
            );
            final approve = FilledButton(
              onPressed: _busy ? null : () => _act(widget.onApprove),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Approve'),
            );
            if (c.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  approve,
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: edit),
                    const SizedBox(width: 8),
                    Expanded(child: reject),
                  ]),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: edit),
                const SizedBox(width: 8),
                Expanded(child: reject),
                const SizedBox(width: 8),
                Expanded(child: approve),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _ApprovalSignedRow extends StatefulWidget {
  final LandLeadSignedRequest request;
  final LandLead? lead;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;

  const _ApprovalSignedRow({
    required this.request,
    required this.lead,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<_ApprovalSignedRow> createState() => _ApprovalSignedRowState();
}

class _ApprovalSignedRowState extends State<_ApprovalSignedRow> {
  bool _busy = false;

  Future<void> _act(Future<void> Function()? fn) async {
    if (fn == null || _busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final lead = widget.lead;
    final ownerLabel = lead?.displayName ?? 'Lead #${req.leadId}';
    final attachments = req.photoUrls.length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: LeadStatus.signed.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: LeadStatus.signed.color.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: LeadStatus.signed.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.check_circle,
                    color: LeadStatus.signed.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Signed · $ownerLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (req.requestedByName.isNotEmpty) req.requestedByName,
                        '$attachments file${attachments == 1 ? '' : 's'}',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (req.note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              req.note.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: context.fomraTextSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _act(widget.onReject),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                        color: AppColors.error.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _act(widget.onApprove),
                  style: FilledButton.styleFrom(
                    backgroundColor: LeadStatus.signed.color,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Approve & Sign'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovalDropRow extends StatefulWidget {
  final LeadDropApprovalRequest request;
  final LandLead? lead;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;

  const _ApprovalDropRow({
    required this.request,
    required this.lead,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<_ApprovalDropRow> createState() => _ApprovalDropRowState();
}

class _ApprovalDropRowState extends State<_ApprovalDropRow> {
  bool _busy = false;

  Future<void> _act(Future<void> Function()? fn) async {
    if (fn == null || _busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final lead = widget.lead;
    final ownerLabel = lead?.displayName ?? 'Lead #${req.leadId}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.cancel_schedule_send_outlined,
                    color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Drop request · $ownerLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (req.requestedByName.isNotEmpty) req.requestedByName,
                        req.reason.label,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (req.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              req.notes.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: context.fomraTextSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _act(widget.onReject),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                        color: AppColors.error.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _act(widget.onApprove),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Approve & Drop'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovalVisitRow extends StatefulWidget {
  final LandLeadSiteVisit visit;
  final LandLead? lead;
  final Future<void> Function() onReview;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  const _ApprovalVisitRow({
    required this.visit,
    required this.lead,
    required this.onReview,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<_ApprovalVisitRow> createState() => _ApprovalVisitRowState();
}

class _ApprovalVisitRowState extends State<_ApprovalVisitRow> {
  bool _busy = false;

  Future<void> _act(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visit = widget.visit;
    final lead = widget.lead;
    final displayName = lead?.displayName ?? 'Lead #${visit.leadId}';
    final showId = displayName != 'Lead #${visit.leadId}';
    final subtitleParts = <String>[
      displayName,
      if (showId) '#${visit.leadId}',
      if (visit.loggedByName.isNotEmpty) 'Requested by ${visit.loggedByName}',
      _portalFormatVisitDateTime(visit.visitedAt.toLocal()),
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : () => _act(widget.onReview),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: context.fomraSurfaceVar.withValues(
              alpha: context.isDarkMode ? 0.55 : 0.65,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.fomraBorder),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 520;
              final info = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.apartment_outlined,
                      color: AppColors.warning,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Management site visit',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitleParts.join(' · '),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final actions = _busy
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(
                          onPressed: () => _act(widget.onReject),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.45),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Reject'),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: () => _act(widget.onApprove),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Approve'),
                        ),
                      ],
                    );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    info,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 12),
                  actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class PortalTeamPerf {
  final String name;
  final String designation;
  final int total;
  final int today;
  final double percent;
  final int rank;
  final String statusLabel;
  final StatusTone tone;

  const PortalTeamPerf({
    required this.name,
    required this.designation,
    required this.total,
    required this.today,
    required this.percent,
    required this.rank,
    required this.statusLabel,
    required this.tone,
  });

  PortalTeamPerf copyWith({int? rank}) => PortalTeamPerf(
        name: name,
        designation: designation,
        total: total,
        today: today,
        percent: percent,
        rank: rank ?? this.rank,
        statusLabel: statusLabel,
        tone: tone,
      );
}

int _leadStatusPerformanceWeight(LeadStatus status) {
  return switch (status) {
    LeadStatus.signed => 100,
    LeadStatus.legal => 80,
    LeadStatus.negotiation => 65,
    // Management meeting completed sits between the owner meeting and
    // negotiation in the pipeline.
    LeadStatus.managementMeetingCompleted => 55,
    LeadStatus.prospectMeetingCompleted => 45,
    LeadStatus.prospectMeetingPending => 25,
    LeadStatus.onHold => 20,
    LeadStatus.dropped => 0,
  };
}

double _conversionScore(List<LandLead> leads) {
  if (leads.isEmpty) return 0;
  final signed = leads.where((l) => l.status == LeadStatus.signed).length;
  return signed / leads.length;
}

double _statusScore(List<LandLead> leads) {
  if (leads.isEmpty) return 0;
  final sum = leads.fold<double>(
    0,
    (acc, lead) => acc + _leadStatusPerformanceWeight(lead.status),
  );
  return (sum / leads.length) / 100;
}

double _compositePerformanceScore({
  required List<LandLead> leads,
  required int maxCount,
}) {
  final conversionScore = _conversionScore(leads);
  final statusScore = _statusScore(leads);
  final volumeScore = maxCount == 0 ? 0.0 : leads.length / maxCount;
  return (0.40 * conversionScore +
          0.35 * statusScore +
          0.25 * volumeScore)
      .clamp(0.0, 1.0);
}

(String, StatusTone) _performanceStatusFromScore(double score) {
  return switch (score) {
    >= 0.80 => ('Top performer', StatusTone.success),
    >= 0.55 => ('On track', StatusTone.primary),
    >= 0.30 => ('Needs boost', StatusTone.warning),
    _ => ('Low activity', StatusTone.danger),
  };
}

List<PortalTeamPerf> buildPortalTeamPerformance(List<LandLead> leads) {
  final employeeMap = <String, String>{};
  for (final employee in AppStore.instance.employees) {
    if (employee.fullName.trim().isEmpty) continue;
    employeeMap[employee.fullName.trim()] = employee.designation.trim();
  }

  final now = DateTime.now();
  final byUser = <String, List<LandLead>>{};
  for (final lead in leads) {
    final name = lead.createdByName.trim();
    if (name.isEmpty || name.toLowerCase() == 'management') continue;
    byUser.putIfAbsent(name, () => []).add(lead);
  }

  final maxCount = byUser.values.isEmpty
      ? 1
      : byUser.values.map((e) => e.length).reduce((a, b) => a > b ? a : b);

  final rows = byUser.entries.map((entry) {
    final personLeads = entry.value;
    final total = personLeads.length;
    final today =
        personLeads.where((l) => portalIsSameDay(l.addedOn, now)).length;
    final composite = _compositePerformanceScore(
      leads: personLeads,
      maxCount: maxCount,
    );
    final status = _performanceStatusFromScore(composite);
    return PortalTeamPerf(
      name: entry.key,
      designation: employeeMap[entry.key] ?? '',
      total: total,
      today: today,
      percent: composite,
      rank: 0,
      statusLabel: status.$1,
      tone: status.$2,
    );
  }).toList()
    ..sort((a, b) => b.percent.compareTo(a.percent));

  for (var i = 0; i < rows.length; i++) {
    rows[i] = rows[i].copyWith(rank: i + 1);
  }
  return rows;
}

class PortalPerformanceRow extends StatefulWidget {
  final PortalTeamPerf data;
  final List<LandLead> leads;
  final ValueChanged<LandLead>? onViewLead;

  const PortalPerformanceRow({
    super.key,
    required this.data,
    this.leads = const [],
    this.onViewLead,
  });

  @override
  State<PortalPerformanceRow> createState() => _PortalPerformanceRowState();
}

class _PortalPerformanceRowState extends State<PortalPerformanceRow> {
  static const _expandMs = Duration(milliseconds: 280);
  bool _expanded = false;
  bool _hovered = false;

  String _priorityLabel(LandLead lead) {
    return switch (lead.status) {
      LeadStatus.signed => 'Low',
      LeadStatus.dropped => 'Low',
      LeadStatus.onHold => 'Low',
      LeadStatus.prospectMeetingCompleted => 'Medium',
      LeadStatus.legal => 'Medium',
      _ => 'High',
    };
  }

  StatusTone _priorityTone(LandLead lead) {
    return switch (lead.status) {
      LeadStatus.signed => StatusTone.success,
      LeadStatus.dropped => StatusTone.neutral,
      LeadStatus.onHold => StatusTone.neutral,
      LeadStatus.prospectMeetingCompleted => StatusTone.warning,
      LeadStatus.legal => StatusTone.warning,
      _ => StatusTone.danger,
    };
  }

  String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final accent = data.rank == 1
        ? AppColors.warning
        : data.rank == 2
            ? AppColors.primary
            : AppColors.purple;
    final initials = data.name.trim().isEmpty
        ? '?'
        : data.name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((e) => e[0])
            .join();

    final leads = widget.leads;
    final activeLeads = leads.where((l) => l.status.isActive).length;
    final closedLeads = leads.where((l) => l.status.isAcquired).length;
    final conversionRate = leads.isEmpty ? 0 : ((closedLeads / leads.length) * 100).round();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: _expandMs,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: context.fomraSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _expanded
                ? AppColors.primary.withValues(alpha: 0.26)
                : context.fomraBorder.withValues(alpha: _hovered ? 0.9 : 0.75),
          ),
          boxShadow: _hovered || _expanded ? context.fomraCardShadow : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initials.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    data.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: context.fomraTextPrimary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '#${data.rank}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: data.percent),
                              duration: AppMotion.slow,
                              curve: AppMotion.curve,
                              builder: (_, value, __) => Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: value,
                                        minHeight: 4.5,
                                        backgroundColor:
                                            accent.withValues(alpha: 0.12),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(accent),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(value * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: context.fomraTextPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                StatusChip(label: data.statusLabel, tone: data.tone),
                                _TinyStat(label: 'Leads', value: '${data.total}'),
                                _TinyStat(label: 'Today', value: '${data.today}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: _expandMs,
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: context.fomraTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: _expandMs,
                    curve: Curves.easeOutCubic,
                    child: !_expanded
                        ? const SizedBox.shrink()
                        : Column(
                            children: [
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              _PerformanceSummaryRow(
                                totalLeads: leads.length,
                                activeLeads: activeLeads,
                                closedDeals: closedLeads,
                                conversionRate: conversionRate,
                              ),
                              const SizedBox(height: 10),
                              if (leads.isEmpty)
                                _PerformanceEmptyState(name: data.name)
                              else
                                _PerformanceLeadList(
                                  leads: leads,
                                  fmtDate: _fmtDate,
                                  priorityLabel: _priorityLabel,
                                  priorityTone: _priorityTone,
                                  onViewLead: widget.onViewLead,
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PerformanceSummaryRow extends StatelessWidget {
  final int totalLeads;
  final int activeLeads;
  final int closedDeals;
  final int conversionRate;

  const _PerformanceSummaryRow({
    required this.totalLeads,
    required this.activeLeads,
    required this.closedDeals,
    required this.conversionRate,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _TinyStat(label: 'Total Sites', value: '$totalLeads'),
        _TinyStat(label: 'Active Sites', value: '$activeLeads'),
        _TinyStat(label: 'Closed Deals', value: '$closedDeals'),
        _TinyStat(label: 'Conversion Rate', value: '$conversionRate%'),
      ],
    );
  }
}

StatusTone _statusTone(LeadStatus status) {
  return switch (status) {
    LeadStatus.prospectMeetingPending => StatusTone.primary,
    LeadStatus.prospectMeetingCompleted => StatusTone.warning,
    LeadStatus.managementMeetingCompleted => StatusTone.primary,
    LeadStatus.negotiation => StatusTone.danger,
    LeadStatus.legal => StatusTone.warning,
    LeadStatus.signed => StatusTone.success,
    LeadStatus.dropped => StatusTone.neutral,
    LeadStatus.onHold => StatusTone.neutral,
  };
}

class _PerformanceLeadList extends StatelessWidget {
  final List<LandLead> leads;
  final String Function(DateTime) fmtDate;
  final String Function(LandLead) priorityLabel;
  final StatusTone Function(LandLead) priorityTone;
  final ValueChanged<LandLead>? onViewLead;

  const _PerformanceLeadList({
    required this.leads,
    required this.fmtDate,
    required this.priorityLabel,
    required this.priorityTone,
    required this.onViewLead,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LeadHeaderRow(),
        const SizedBox(height: 8),
        for (final lead in leads) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: context.fomraSurfaceVar.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.fomraBorder.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 18,
                  child: Text(
                    lead.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextPrimary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 20,
                  child: Text(
                    '${lead.landType.label} • ${lead.village.isNotEmpty ? lead.village : lead.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.fomraTextSecondary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 11,
                  child: StatusChip(label: lead.status.label, tone: _statusTone(lead.status)),
                ),
                Expanded(
                  flex: 9,
                  child: StatusChip(label: priorityLabel(lead), tone: priorityTone(lead)),
                ),
                Expanded(
                  flex: 10,
                  child: Text(
                    fmtDate(lead.addedOn.toLocal()),
                    style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
                  ),
                ),
                Expanded(
                  flex: 10,
                  child: Text(
                    fmtDate(lead.addedOn.toLocal()),
                    style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onViewLead == null ? null : () => onViewLead!(lead),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('View'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (lead != leads.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _LeadHeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    TextStyle style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: context.fomraTextSecondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(flex: 18, child: Text('Lead Name', style: style)),
          Expanded(flex: 20, child: Text('Property / Location', style: style)),
          Expanded(flex: 11, child: Text('Current Stage', style: style)),
          Expanded(flex: 9, child: Text('Priority', style: style)),
          Expanded(flex: 10, child: Text('Last Activity', style: style)),
          Expanded(flex: 10, child: Text('Assigned Date', style: style)),
          Expanded(flex: 7, child: Text('Action', style: style)),
        ],
      ),
    );
  }
}

class _PerformanceEmptyState extends StatelessWidget {
  final String name;
  const _PerformanceEmptyState({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.fomraSurfaceVar.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.fomraBorder.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, color: context.fomraTextSecondary),
          const SizedBox(height: 8),
          Text(
            'No leads assigned to $name',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Leads assigned to this employee will appear here.',
            style: TextStyle(fontSize: 12, color: context.fomraTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _TinyStat extends StatelessWidget {
  final String label;
  final String value;

  const _TinyStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.fomraSurfaceVar,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.fomraTextSecondary,
        ),
      ),
    );
  }
}

class PortalSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  const PortalSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: AppColors.radiusLg,
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: title,
            subtitle: subtitle,
            icon: icon,
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
          ),
          child,
        ],
      ),
    );
  }
}

/// Wider home content — ~94% of viewport on desktop.
Widget portalHomeWidthConstraint(BuildContext context, Widget child) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final isWide = FomraLayout.isDesktop(context);
      final maxW = isWide ? constraints.maxWidth * 0.94 : constraints.maxWidth;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: child,
        ),
      );
    },
  );
}

class PortalEmptyHint extends StatelessWidget {
  final String hint;

  const PortalEmptyHint({super.key, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        hint,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: context.fomraTextTertiary,
        ),
      ),
    );
  }
}

/// Premium profile dropdown anchored to a tap on the home header chip.
Future<String?> showPortalProfileMenu({
  required BuildContext context,
  required Offset anchor,
  required String name,
  required String role,
  required String initial,
  String? email,
}) {
  final media = MediaQuery.of(context);
  const menuWidth = 252.0;
  var left = anchor.dx - menuWidth + 48;
  left = left.clamp(12.0, media.size.width - menuWidth - 12.0);
  final top = (anchor.dy + 10).clamp(
    media.padding.top + 8,
    media.size.height - 280,
  );

  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss profile menu',
    barrierColor: Colors.black.withValues(alpha: 0.08),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: _PortalProfileMenuPanel(
              name: name,
              role: role,
              email: email,
              onSelect: (value) => Navigator.of(context).pop(value),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          alignment: Alignment.topCenter,
          child: child,
        ),
      );
    },
  );
}

class _PortalProfileMenuPanel extends StatelessWidget {
  final String name;
  final String role;
  final String? email;
  final ValueChanged<String> onSelect;

  const _PortalProfileMenuPanel({
    required this.name,
    required this.role,
    this.email,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: context.fomraSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.fomraBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F0F172A),
              blurRadius: 32,
              offset: Offset(0, 12),
            ),
            BoxShadow(
              color: Color(0x0A0F172A),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    ProfileAvatar(
                      email: email,
                      name: name,
                      radius: 20,
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.fomraTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.fomraTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.fomraBorder),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Builder(
                  builder: (context) {
                    final hasPhoto =
                        ProfilePhotoService.instance.hasPhotoFor(email);
                    return _PortalProfileMenuItem(
                      icon: hasPhoto
                          ? Icons.edit_outlined
                          : Icons.add_a_photo_outlined,
                      label: hasPhoto
                          ? 'Edit Profile Photo'
                          : 'Upload Profile Photo',
                      subtitle: hasPhoto
                          ? 'Re-crop or replace it'
                          : 'Set your account picture',
                      onTap: () => onSelect('upload_photo'),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: _PortalProfileMenuItem(
                  icon: Icons.lock_outline_rounded,
                  label: 'Change Password',
                  subtitle: 'Update your password',
                  onTap: () => onSelect('change_password'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Divider(height: 1, color: context.fomraBorder),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: _PortalProfileMenuItem(
                  icon: Icons.logout_rounded,
                  label: 'Sign Out',
                  destructive: true,
                  onTap: () => onSelect('sign_out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalProfileMenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;

  const _PortalProfileMenuItem({
    required this.icon,
    required this.label,
    this.subtitle,
    this.destructive = false,
    required this.onTap,
  });

  @override
  State<_PortalProfileMenuItem> createState() => _PortalProfileMenuItemState();
}

class _PortalProfileMenuItemState extends State<_PortalProfileMenuItem> {
  bool _hovered = false;

  static const _destructive = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.destructive ? _destructive : context.fomraTextPrimary;
    final iconColor = widget.destructive ? _destructive : AppColors.primary;
    final hoverBg = context.fomraHoverBg;
    final iconBg = context.fomraIconChipBg;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: widget.subtitle == null ? 50 : 52,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _hovered ? hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  scale: _hovered ? 1.06 : 1,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.destructive
                          ? _destructive.withValues(alpha: 0.08)
                          : iconBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      widget.icon,
                      size: 20,
                      color: iconColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
