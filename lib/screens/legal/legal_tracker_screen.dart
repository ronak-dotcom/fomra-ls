import 'package:flutter/material.dart';

import '../../models/land_lead.dart';
import '../../services/app_store.dart';
import '../../services/document_index_service.dart';
import '../../services/legal_verification_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/legal_document_catalog.dart';
import '../../widgets/land_workspace_ui.dart';
import '../../widgets/lead_filter_bar.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';

import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_loader.dart';
import '../land_lead/lead_detail_screen.dart';
import '../legal_verification/legal_verification_screen.dart';

enum _LegalTrackFilter { all, ecPending, verificationPending, approved, rejected }

/// Tracks EC documents, legal verification, and approvals per lead.
class LegalTrackerScreen extends StatefulWidget {
  const LegalTrackerScreen({super.key});

  @override
  State<LegalTrackerScreen> createState() => _LegalTrackerScreenState();
}

class _LegalTrackerScreenState extends State<LegalTrackerScreen> {
  final Map<String, Map<String, dynamic>> _reviews = {};
  bool _loading = true;
  String _query = '';
  final LandWorkspaceFilters _leadFilters = LandWorkspaceFilters();
  _LegalTrackFilter _filter = _LegalTrackFilter.all;

  @override
  void initState() {
    super.initState();
    AppStore.instance.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await DocumentIndexService.instance.ensureLoaded();
      final rows = await LegalVerificationService.getAll();
      if (!mounted) return;
      setState(() {
        _reviews
          ..clear()
          ..addEntries(rows.map((r) => MapEntry(r['lead_id'] as String, r)));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _hasEc(String leadId) {
    return DocumentIndexService.instance.documents.any((d) =>
        d.leadId == leadId &&
        LegalDocumentCatalog.classify(d.fileName) == LegalDocCategory.ec);
  }

  String _result(String leadId) =>
      (_reviews[leadId]?['legal_result'] as String? ?? '').trim().toUpperCase();

  bool _hasVerification(String leadId) {
    final row = _reviews[leadId];
    if (row == null) return false;
    return (row['ownership'] as String? ?? '').trim().isNotEmpty ||
        (row['legal_result'] as String? ?? '').trim().isNotEmpty ||
        (row['encumbrances'] as String? ?? '').trim().isNotEmpty;
  }

  bool _matches(LandLead lead) {
    if (!_leadFilters.matches(lead)) return false;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay =
          '${lead.leadId} ${lead.ownerName} ${lead.village} ${lead.surveyNumber}'
              .toLowerCase();
      if (!hay.contains(q)) return false;
    }
    final result = _result(lead.leadId);
    final hasEc = _hasEc(lead.leadId);
    final verified = _hasVerification(lead.leadId);
    return switch (_filter) {
      _LegalTrackFilter.all => true,
      _LegalTrackFilter.ecPending => !hasEc,
      _LegalTrackFilter.verificationPending => !verified,
      _LegalTrackFilter.approved =>
        result.contains('APPROVE') || result == 'CLEAR',
      _LegalTrackFilter.rejected =>
        result.contains('REJECT') || result.contains('HOLD'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final leads = AppStore.instance.visibleLeads.where(_matches).toList();
    final ecDone =
        AppStore.instance.visibleLeads.where((l) => _hasEc(l.leadId)).length;
    final verified =
        AppStore.instance.visibleLeads.where((l) => _hasVerification(l.leadId)).length;
    final approved = AppStore.instance.visibleLeads
        .where((l) {
          final r = _result(l.leadId);
          return r.contains('APPROVE') || r == 'CLEAR';
        })
        .length;

    return FomraAppShell(
      currentRoute: '/legal-tracker',
      appBar: const FomraAppBar(
        moduleName: 'Legal Tracker',

      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: FomraLayout.pagePadding(context),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Legal Tracker',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: context.fomraTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'EC · Legal verification · Approvals',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.fomraTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalVerificationScreen(),
                    ),
                  ),
                  child: const Text('Open verification'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _kpi('EC filed', '$ecDone', AppColors.info),
                _kpi('Verified', '$verified', AppColors.primary),
                _kpi('Approved', '$approved', AppColors.success),
              ],
            ),
            const SizedBox(height: 12),
            LeadFilterBar(
              filters: _leadFilters,
              onChanged: () => setState(() {}),
              onSearch: (v) => setState(() => _query = v),
              hintText: 'Search leads…',
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _LegalTrackFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (f) {
                          _LegalTrackFilter.all => 'All',
                          _LegalTrackFilter.ecPending => 'EC pending',
                          _LegalTrackFilter.verificationPending =>
                            'Verification pending',
                          _LegalTrackFilter.approved => 'Approved',
                          _LegalTrackFilter.rejected => 'Rejected / Hold',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              Padding(
                padding: const EdgeInsets.all(32),
                child: AppLoader.center(message: 'Loading legal records…'),
              )
            else if (leads.isEmpty)
              const AppCard(
                child: EmptyState(
                  title: 'No matching leads',
                  message: 'Adjust filters or add legal documents / reviews.',
                ),
              )
            else
              ...leads.map((lead) {
                final hasEc = _hasEc(lead.leadId);
                final verified = _hasVerification(lead.leadId);
                final result = _result(lead.leadId);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LeadDetailScreen(lead: lead),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lead.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            'Lead #${lead.leadId}',
                            if (lead.village.isNotEmpty) lead.village,
                            lead.status.label,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _statusChip('EC', hasEc),
                            _statusChip('Verification', verified),
                            _statusChip(
                              result.isEmpty ? 'Approval' : result,
                              result.contains('APPROVE') || result == 'CLEAR',
                              pending: result.isEmpty,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _statusChip(String label, bool done, {bool pending = false}) {
    final color = pending
        ? AppColors.warning
        : done
            ? AppColors.success
            : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label · ${pending ? 'Pending' : done ? 'Done' : 'Missing'}',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
