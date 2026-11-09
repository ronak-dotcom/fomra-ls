import 'package:flutter/material.dart';

import '../../models/land_lead.dart';
import '../../models/land_lead_meeting.dart';
import '../../services/app_store.dart';
import '../../services/land_lead_meeting_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/contact_call_whatsapp.dart';
import '../../widgets/land_workspace_ui.dart';
import '../../widgets/lead_filter_bar.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';

import '../../widgets/lead_portfolio_breakdown.dart';
import '../../widgets/ui/app_components.dart';
import '../land_lead/lead_detail_screen.dart';

class _OwnerHistoryGroup {
  final String ownerKey;
  final String ownerName;
  final String contact;
  final List<LandLead> leads;

  const _OwnerHistoryGroup({
    required this.ownerKey,
    required this.ownerName,
    required this.contact,
    required this.leads,
  });

  int get negotiations =>
      leads.where((l) => l.status == LeadStatus.negotiation).length;
}

/// Historical negotiations grouped by landowner.
class OwnerHistoryScreen extends StatefulWidget {
  const OwnerHistoryScreen({super.key});

  @override
  State<OwnerHistoryScreen> createState() => _OwnerHistoryScreenState();
}

class _OwnerHistoryScreenState extends State<OwnerHistoryScreen> {
  String _query = '';
  String? _expandedKey;
  final LandWorkspaceFilters _leadFilters = LandWorkspaceFilters();

  @override
  void initState() {
    super.initState();
    AppStore.instance.addListener(_rebuild);
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  List<_OwnerHistoryGroup> get _groups {
    final map = <String, List<LandLead>>{};
    for (final lead in AppStore.instance.visibleLeads) {
      if (!_leadFilters.matches(lead)) continue;
      final name = lead.ownerName.trim();
      if (name.isEmpty) continue;
      final contact = lead.contactDetails.replaceAll(RegExp(r'[^\d+]'), '');
      final key = '${name.toLowerCase()}|$contact';
      (map[key] ??= []).add(lead);
    }
    final q = _query.trim().toLowerCase();
    final groups = map.entries.map((e) {
      final leads = e.value
        ..sort((a, b) => b.addedOn.compareTo(a.addedOn));
      return _OwnerHistoryGroup(
        ownerKey: e.key,
        ownerName: leads.first.ownerName.trim(),
        contact: leads
            .map((l) => l.contactDetails.trim())
            .firstWhere((c) => c.isNotEmpty, orElse: () => ''),
        leads: leads,
      );
    }).where((g) {
      if (q.isEmpty) return true;
      return g.ownerName.toLowerCase().contains(q) ||
          g.contact.contains(q) ||
          g.leads.any((l) =>
              l.village.toLowerCase().contains(q) ||
              l.leadId.toLowerCase().contains(q));
    }).toList()
      ..sort((a, b) => b.leads.length.compareTo(a.leads.length));
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;

    return FomraAppShell(
      currentRoute: '/owner-history',
      appBar: const FomraAppBar(
        moduleName: 'Owner History',

      ),
      body: ListView(
        padding: FomraLayout.pagePadding(context),
        children: [
          Text(
            'Owner History',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Historical negotiations by landowner.',
            style: TextStyle(fontSize: 13, color: context.fomraTextSecondary),
          ),
          const SizedBox(height: 14),
          LeadFilterBar(
            filters: _leadFilters,
            onChanged: () => setState(() {}),
            onSearch: (v) => setState(() => _query = v),
            hintText: 'Search owner, contact, village…',
          ),
          const SizedBox(height: 14),
          if (groups.isEmpty)
            const AppCard(
              child: EmptyState(
                title: 'No owner history',
                message: 'Owners appear when leads include an owner name. '
                    'If filters are applied, try clearing them.',
              ),
            )
          else
            ...groups.map((g) {
              final expanded = _expandedKey == g.ownerKey;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => setState(() {
                    _expandedKey = expanded ? null : g.ownerKey;
                  }),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              g.ownerName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: context.fomraTextPrimary,
                              ),
                            ),
                          ),
                          ContactCallWhatsApp(
                            contact: g.contact,
                            accent: AppColors.success,
                          ),
                          Icon(
                            expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: context.fomraTextSecondary,
                          ),
                        ],
                      ),
                      if (g.contact.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          g.contact,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          _chip('${g.leads.length} lead(s)'),
                          _chip('${g.negotiations} negotiation'),
                        ],
                      ),
                      if (expanded) ...[
                        const SizedBox(height: 14),
                        _OwnerPortfolioSection(leads: g.leads),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.fomraSurfaceVar,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );
}

/// An owner's linked leads, plus — when any of them were dropped — the total
/// Land Owner Meetings that were conducted on those dropped leads.
class _OwnerPortfolioSection extends StatefulWidget {
  final List<LandLead> leads;

  const _OwnerPortfolioSection({required this.leads});

  @override
  State<_OwnerPortfolioSection> createState() => _OwnerPortfolioSectionState();
}

class _OwnerPortfolioSectionState extends State<_OwnerPortfolioSection> {
  int? _meetingsConducted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _OwnerPortfolioSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leads != widget.leads) _load();
  }

  Future<void> _load() async {
    final leads = widget.leads;
    if (leads.isEmpty) {
      if (mounted) setState(() => _meetingsConducted = null);
      return;
    }
    try {
      final lists = await Future.wait<List<LandLeadMeeting>>(
        leads.map((l) => LandLeadMeetingService.getForLead(l.leadId)),
      );
      if (!mounted) return;
      setState(() =>
          _meetingsConducted = lists.fold<int>(0, (s, m) => s + m.length));
    } catch (_) {
      // Leave the card off rather than show a wrong count.
      if (mounted) setState(() => _meetingsConducted = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LeadPortfolioBreakdown(
      leads: widget.leads,
      meetingsBesideDropped: _meetingsConducted,

      hideEmptyStatusCards: true,
      onOpenLead: (lead) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LeadDetailScreen(lead: lead)),
      ),
    );
  }
}
