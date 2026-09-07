import 'package:flutter/material.dart';
import '../../models/land_lead.dart';
import '../../models/lead_list_filter.dart';
import '../../models/employee_profile.dart';
import '../../services/app_store.dart';
import '../../services/auth_service.dart';
import '../../services/document_index_service.dart';
import '../../services/employee_service.dart';
import '../../services/land_lead_service.dart';
import '../../services/notifications_service.dart';
import '../../services/role_access.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/legal_document_catalog.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/land_workspace_ui.dart';
import '../../widgets/management_executive_dashboard.dart';
import '../../widgets/portal_home_sections.dart';
import '../../widgets/portal_page_layout.dart';
import '../../widgets/ui/app_components.dart';
import 'add_lead_screen.dart';
import 'filtered_leads_screen.dart';
import 'lead_detail_screen.dart';
import 'leads_map_screen.dart';
import 'meeting_log_dialog.dart';

class LandLeadScreen extends StatefulWidget {
  final bool isTab;
  const LandLeadScreen({super.key, this.isTab = false});

  @override
  State<LandLeadScreen> createState() => _LandLeadScreenState();
}

class _LandLeadScreenState extends State<LandLeadScreen> {
  String _search = '';
  bool _loading = true;
  String? _loadError;

  final LandWorkspaceFilters _filters = LandWorkspaceFilters();

  bool _selectMode = false;
  bool _showDistrict = false;
  final Set<String> _selectedLeadIds = {};

  @override
  void initState() {
    super.initState();
    AppStore.instance.addListener(_onStoreUpdate);
    _loadLeads();
    if (AuthService.instance.isManagement) _loadEmployees();
    DocumentIndexService.instance.ensureLoaded();
  }

  bool get _isManagement => AuthService.instance.isManagement;

  /// Employee names management can assign leads to.
  List<String> get _employeeNames => AppStore.instance.employees
      .where((e) => e.status == EmployeeStatus.active)
      .map((e) => e.fullName)
      .toList();

  /// Names to offer when assigning [leadIds]: drops anyone who is already the
  /// assignee of every selected lead (assigning to them would be a no-op).
  List<String> _assignableNamesFor(Set<String> leadIds) {
    final selected = AppStore.instance.leads
        .where((l) => leadIds.contains(l.leadId))
        .toList();
    if (selected.isEmpty) return _employeeNames;
    return _employeeNames.where((n) {
      final name = n.trim().toLowerCase();
      final ownsEvery = selected
          .every((l) => l.assignedToName.trim().toLowerCase() == name);
      return !ownsEvery;
    }).toList();
  }

  Future<void> _loadEmployees() async {
    if (AppStore.instance.employees.isNotEmpty) return;
    try {
      final list = await EmployeeService.getAll();
      if (list.isNotEmpty) AppStore.instance.setEmployees(list);
    } catch (_) {/* assignment picker just stays empty */}
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selectedLeadIds.clear();
    });
  }

  void _toggleLeadSelected(LandLead lead) {
    setState(() {
      if (!_selectedLeadIds.remove(lead.leadId)) {
        _selectedLeadIds.add(lead.leadId);
      }
    });
  }

  LeadListFilter? _summaryFilterFor(LeadStatus? status) {
    return switch (status) {
      LeadStatus.negotiation => LeadListFilter.negotiation,
      LeadStatus.legal => LeadListFilter.legal,
      LeadStatus.signed => LeadListFilter.signed,
      LeadStatus.dropped => LeadListFilter.dropped,
      null => LeadListFilter.prospect,
      _ => null,
    };
  }

  void _openSummaryFilter(LeadStatus? status, String title) {
    final filter = _summaryFilterFor(status);
    if (filter == null) return;
    FilteredLeadsScreen.open(context, filter);
  }

  /// Ask which employee to assign the selected leads to, confirm, then assign.
  Future<void> _assignSelected() async {
    if (_selectedLeadIds.isEmpty) return;
    final names = _assignableNamesFor(_selectedLeadIds);
    if (names.isEmpty) {
      AppFeedback.info(
          context, 'No other employees to assign these lead(s) to.');
      return;
    }

    // 1) Pick employee.
    final name = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.fomraSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(children: [
              Text('Assign ${_selectedLeadIds.length} lead(s) to',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextPrimary)),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: names
                  .map((n) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.12),
                          child: Text(n.isNotEmpty ? n[0].toUpperCase() : '?',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(n),
                        onTap: () => Navigator.pop(ctx, n),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (name == null || !mounted) return;

    // 2) Confirm.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign leads?'),
        content: Text(
            'Assign ${_selectedLeadIds.length} lead(s) to $name? '
            'They will move to $name\'s leads page and $name will be notified.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Assign')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _assignLeadsTo(_selectedLeadIds.toList(), name);
  }

  void _assignLeadsTo(List<String> leadIds, String name) {
    final all = AppStore.instance.leads;
    final employee = AppStore.instance.employees
        .where((e) => e.fullName.trim() == name.trim())
        .cast<EmployeeProfile?>()
        .firstOrNull;
    for (final id in leadIds) {
      final lead = all.where((l) => l.leadId == id).cast<LandLead?>().firstOrNull;
      if (lead == null || lead.assignedToName == name) continue;
      final previousAssignee = lead.assignedToName;
      AppStore.instance.replaceLead(lead.copyWith(assignedToName: name));
      LandLeadService.assignTo(id, name, employeeEmail: employee?.email ?? '')
          .catchError((_) {
        AppStore.instance
            .replaceLead(lead.copyWith(assignedToName: previousAssignee));
      });
    }
    // One targeted notification for the assignee.
    NotificationsService.create(
      audience: 'employee',
      type: 'assigned_lead',
      title: 'Leads assigned to you',
      leadId: leadIds.length == 1 ? leadIds.first : null,
      message: '${leadIds.length} lead(s) — assigned to $name',
    ).catchError((_) {});

    setState(() {
      _selectMode = false;
      _selectedLeadIds.clear();
    });
    if (mounted) {
      AppFeedback.success(
          context, '${leadIds.length} lead(s) assigned to $name');
    }
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_onStoreUpdate);
    super.dispose();
  }

  void _onStoreUpdate() => setState(() {});

  /// Extracts a readable message from Supabase (PostgrestException/AuthException)
  /// or any other error so failures are diagnosable instead of generic.
  String _errMsg(Object e) {
    try {
      final m = (e as dynamic).message;
      if (m is String && m.isNotEmpty) return m;
    } catch (_) {}
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _loadLeads() async {
    if (mounted) setState(() { _loading = true; _loadError = null; });
    try {
      final leads = await LandLeadService.getAll();
      AppStore.instance.setLeads(leads);
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Failed to load leads: ${_errMsg(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Management sees every lead; an employee sees only the leads they added.
  List<LandLead> get _leads => AppStore.instance.visibleLeads;

  List<LandLead> get _filtered =>
      _leads.where((l) => _filters.matches(l) && _matchesSearch(l)).toList();

  bool _matchesSearch(LandLead l) {
    final q = _search.toLowerCase();
    if (q.isEmpty) return true;
    return l.ownerName.toLowerCase().contains(q) ||
        l.location.toLowerCase().contains(q) ||
        l.surveyNumber.toLowerCase().contains(q) ||
        l.leadId.toLowerCase().contains(q) ||
        l.contactDetails.toLowerCase().contains(q) ||
        l.village.toLowerCase().contains(q) ||
        l.taluk.toLowerCase().contains(q) ||
        l.district.toLowerCase().contains(q) ||
        l.brokerName.toLowerCase().contains(q) ||
        l.brokerContact.toLowerCase().contains(q) ||
        _docNumberMatches(l.leadId, q);
  }

  bool _docNumberMatches(String leadId, String q) {
    for (final d in DocumentIndexService.instance.documents) {
      if (d.leadId != leadId) continue;
      if (d.fileName.toLowerCase().contains(q)) return true;
      final num = LegalDocumentCatalog.extractDocumentNumber(d.fileName);
      if (num != null && num.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  int get _activeFilterCount => _filters.activeCount;

  void _clearAllFilters() {
    setState(_filters.clear);
  }

  void _applyFilters(LandWorkspaceFilters next) {
    setState(() {
      _filters.status = next.status;
      _filters.statuses
        ..clear()
        ..addAll(next.statuses);
      _filters.landTypes
        ..clear()
        ..addAll(next.landTypes);
      _filters.sources
        ..clear()
        ..addAll(next.sources);
      _filters.highPriority = next.highPriority;
      _filters.assignedEmployee = next.assignedEmployee;
      _filters.assignedEmployees
        ..clear()
        ..addAll(next.assignedEmployees);
      _filters.createdFrom = next.createdFrom;
      _filters.createdTo = next.createdTo;
      _filters.district = next.district;
      _filters.districts
        ..clear()
        ..addAll(next.districts);
      _filters.taluk = next.taluk;
      _filters.taluks
        ..clear()
        ..addAll(next.taluks);
      _filters.village = next.village;
      _filters.villages
        ..clear()
        ..addAll(next.villages);
      _filters.broker = next.broker;
      _filters.brokers
        ..clear()
        ..addAll(next.brokers);
      _filters.acresMin = next.acresMin;
      _filters.acresMax = next.acresMax;
      _filters.pendingStatus = next.pendingStatus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildScrollableBody();

    // Users with create access get the "+" Add Lead FAB (Management included).
    final fab = RoleAccess.canCreate
        ? LandWorkspaceSpeedDial(
            onAddLead: _openAddLead,
          )
        : null;

    if (widget.isTab) {
      return Scaffold(
        backgroundColor: context.fomraPageBg,
        body: body,
        floatingActionButton: fab,
      );
    }
    return FomraAppShell(
      currentRoute: '/land-lead',
      appBar: const FomraAppBar(
        moduleName: 'Land Workspace',
      ),
      body: body,
      floatingActionButton: fab,
    );
  }

  /// Always-visible management actions shown next to the lead summary:
  /// Select (enter assign mode) and View all leads (open the leads map), with
  /// the District Performance toggle sitting directly below View all leads.
  Widget _buildIdleManagementActions() {
    final select = _actionPill(
      onTap: _toggleSelectMode,
      icon: Icons.checklist_rtl,
      label: 'Select',
    );
    final viewAll = _actionPill(
      onTap: _openLeadsMap,
      icon: Icons.map_outlined,
      label: 'View all leads',
      foreground: const Color(0xFF0F766E),
      background: const Color(0xFF0F766E).withValues(alpha: 0.10),
    );
    final district = _actionPill(
      onTap: () => setState(() => _showDistrict = !_showDistrict),
      icon: _showDistrict ? Icons.list_alt_outlined : Icons.insights_outlined,
      label: _showDistrict ? 'Back to Leads' : 'District Performance',
      foreground: AppColors.purple,
      background: AppColors.purple.withValues(alpha: 0.10),
    );
    // Mobile: let the pills flow and wrap (full width / two per row) instead of
    // crowding to the right of the summary.
    if (FomraLayout.isMobile(context)) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [select, viewAll, district],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            select,
            const SizedBox(width: 8),
            viewAll,
          ],
        ),
        const SizedBox(height: 8),
        district,
      ],
    );
  }

  Widget _actionPill({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    Color? foreground,
    Color? background,
  }) {
    final fg = foreground ?? AppColors.primary;
    final bg = background ?? AppColors.primary.withValues(alpha: 0.10);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: fg.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
          ]),
        ),
      ),
    );
  }

  Widget _buildSelectBar() {
    if (!_selectMode) return const SizedBox.shrink();
    final count = _selectedLeadIds.length;
    final canAssign = count > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.primary.withValues(alpha: 0.05),
          ]),
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            child: Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Text(count == 1 ? 'lead selected' : 'leads selected',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: context.fomraTextPrimary)),
          const Spacer(),
          TextButton(
            onPressed: _toggleSelectMode,
            style: TextButton.styleFrom(
                foregroundColor: context.fomraTextSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canAssign ? _assignSelected : null,
              borderRadius: BorderRadius.circular(999),
              child: Opacity(
                opacity: canAssign ? 1 : 0.45,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF2563EB)]),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: canAssign
                        ? AppColors.coloredShadow(AppColors.primary)
                        : null,
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_add_alt_1,
                        size: 17, color: Colors.white),
                    SizedBox(width: 7),
                    Text('Assign',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildScrollableBody() {
    if (_loading) {
      return portalPageBody(context, const _LeadsLoadingSkeleton());
    }

    if (_loadError != null) {
      return portalPageBody(
        context,
        EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Couldn’t load leads',
          message: _loadError,
          action: PrimaryButton(
            label: 'Retry',
            icon: Icons.refresh,
            onPressed: _loadLeads,
          ),
        ),
      );
    }

    final pagePad = FomraLayout.pagePadding(context);

    final slivers = <Widget>[
      if (_isManagement && _selectMode && _leads.isNotEmpty)
        SliverToBoxAdapter(
          child: PortalFadeSection(index: 0, child: _buildSelectBar()),
        ),
      if (_leads.isNotEmpty)
        SliverToBoxAdapter(
          child: PortalFadeSection(
            index: 0,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FomraLayout.isMobile(context)
                  // Mobile: summary on top, wrapping action pills beneath it.
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LeadSummary(
                          leads: _leads,
                          onTapStatus: _openSummaryFilter,
                        ),
                        if (_isManagement && !_selectMode) ...[
                          const SizedBox(height: 12),
                          _buildIdleManagementActions(),
                        ],
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _LeadSummary(
                            leads: _leads,
                            onTapStatus: _openSummaryFilter,
                          ),
                        ),
                        if (_isManagement && !_selectMode) ...[
                          const SizedBox(width: 12),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _buildIdleManagementActions(),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      if (_leads.isNotEmpty)
        SliverToBoxAdapter(
          child: PortalFadeSection(
            index: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LandWorkspaceSearchBar(
                  onChanged: (q) => setState(() => _search = q),
                  activeFilterCount: _activeFilterCount,
                  onFilterTap: _openFilterPanel,
                ),
                if (_filters.hasActive) ...[
                  const SizedBox(height: 10),
                  LandWorkspaceActiveFilterChips(
                    filters: _filters,
                    onChanged: () => setState(() {}),
                    onClearAll: _clearAllFilters,
                  ),
                ],
              ],
            ),
          ),
        ),
    ];

    if (_showDistrict) {
      slivers.add(
        SliverPadding(
          padding: pagePad.copyWith(top: 12, bottom: 96),
          sliver: SliverToBoxAdapter(
            child: DistrictPerformanceCard(leads: _filtered),
          ),
        ),
      );
    } else if (_filtered.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyState(
            hasLeads: _leads.isNotEmpty,
            canAddLead: RoleAccess.canCreate,
            onAddLead: _leads.isNotEmpty
                ? _clearAllFilters
                : (RoleAccess.canCreate ? _openAddLead : null),
          ),
        ),
      );
    } else {
      slivers.add(
        SliverPadding(
          padding: pagePad.copyWith(top: 12, bottom: 96),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final lead = _filtered[i];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: i < _filtered.length - 1 ? 8 : 0,
                  ),
                  child: Dismissible(
                    key: ValueKey(lead.leadId),
                    direction: (_selectMode || !RoleAccess.canDelete)
                        ? DismissDirection.none
                        : DismissDirection.endToStart,
                    confirmDismiss: (_) => _confirmAndDelete(lead),
                    background: Container(
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete_outline,
                          color: Colors.white, size: 22),
                    ),
                    child: _LeadListRow(
                      lead: lead,
                      isManagement: _isManagement,
                      selectionMode: _selectMode,
                      selected: _selectedLeadIds.contains(lead.leadId),
                      onTap: _selectMode
                          ? () => _toggleLeadSelected(lead)
                          : () => _openLeadDetail(lead),
                      onView: () => _openLeadDetail(lead),
                      onAssign: _isManagement
                          ? () => _assignSingleLead(lead)
                          : null,
                      onScheduleMeeting: () => _openMeetingForLead(lead),
                      onViewMap: () => _openLeadsMapFor(lead),
                      onEdit: RoleAccess.canEdit
                          ? () => _editLead(lead)
                          : null,
                      onDelete: RoleAccess.canDelete
                          ? () => _confirmAndDelete(lead)
                          : null,
                    ),
                  ),
                );
              },
              childCount: _filtered.length,
            ),
          ),
        ),
      );
    }

    // Full-width scroll view so the scrollbar sits at the window's right edge;
    // content is centered via side padding (same ~94% width as home).
    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            FomraLayout.isDesktop(context) ? constraints.maxWidth * 0.03 : 0.0;
        final pp = pagePad.copyWith(bottom: 0);
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  pp.left + side, pp.top, pp.right + side, pp.bottom),
              sliver: SliverMainAxisGroup(slivers: slivers),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmAndDelete(LandLead lead) async {
    if (!RoleAccess.canDelete) {
      if (mounted) {
        AppFeedback.error(context, RoleAccess.deniedMessage('delete leads'));
      }
      return false;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Lead?'),
            content: Text(
              'This will permanently remove lead ${lead.leadId} (${lead.ownerName}).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return false;

    try {
      await LandLeadService.delete(lead);
      AppStore.instance.removeLead(lead.leadId);
      return true;
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Delete failed: ${_errMsg(e)}');
      }
      return false;
    }
  }

  Future<void> _openAddLead() async {
    if (!RoleAccess.canCreate) {
      if (mounted) {
        AppFeedback.error(context, RoleAccess.deniedMessage('create leads'));
      }
      return;
    }
    final saved = await Navigator.push<LandLead>(
      context,
      MaterialPageRoute(builder: (_) => const AddLeadScreen()),
    );
    if (saved == null) return;

    AppStore.instance.addLead(saved);
    if (mounted) {
      AppFeedback.success(context, 'Lead ${saved.leadId} saved.');
    }
  }

  void _openLeadsMap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LeadsMapScreen(leads: _leads)),
    );
  }

  void _openLeadsMapFor(LandLead lead) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LeadsMapScreen(leads: _leads)),
    );
  }

  void _openLeadDetail(LandLead lead) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LeadDetailScreen(lead: lead)),
    );
  }

  Future<void> _assignSingleLead(LandLead lead) async {
    final names = _assignableNamesFor({lead.leadId});
    if (names.isEmpty) {
      AppFeedback.info(
          context, 'No other employees to assign this lead to.');
      return;
    }

    final name = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.fomraSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(children: [
              Text('Assign lead ${lead.leadId} to',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextPrimary)),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: names
                  .map((n) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.12),
                          child: Text(n.isNotEmpty ? n[0].toUpperCase() : '?',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(n),
                        onTap: () => Navigator.pop(ctx, n),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (name == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign lead?'),
        content: Text(
            'Assign lead ${lead.leadId} to $name? '
            'They will move to $name\'s leads page and $name will be notified.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Assign')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _assignLeadsTo([lead.leadId], name);
  }

  Future<void> _openMeetingForLead(LandLead lead) async {
    await showFomraDialog<void>(
      context: context,
      builder: (ctx) => MeetingLogDialog(
        leadId: lead.leadId,
        ownerName: lead.ownerName,
        onMeetingSaved: () {
          if (lead.status == LeadStatus.prospectMeetingPending) {
            final updated =
                lead.copyWith(status: LeadStatus.prospectMeetingCompleted);
            AppStore.instance.replaceLead(updated);
            LandLeadService.updateStatus(
                    lead.leadId, LeadStatus.prospectMeetingCompleted)
                .catchError((_) {
              AppStore.instance.replaceLead(lead);
            });
          }
        },
      ),
    );
  }

  Future<void> _editLead(LandLead lead) async {
    if (!RoleAccess.canEdit) {
      if (mounted) {
        AppFeedback.error(context, RoleAccess.deniedMessage('edit leads'));
      }
      return;
    }
    final saved = await Navigator.push<LandLead>(
      context,
      MaterialPageRoute(
          builder: (_) => AddLeadScreen(existingLead: lead)),
    );
    if (saved == null) return;
    AppStore.instance.replaceLead(saved);
    if (mounted) {
      AppFeedback.success(context, 'Lead ${saved.leadId} updated.');
    }
  }

  Future<void> _openFilterPanel() async {
    final applied = await showLandWorkspaceFilterPanel(
      context: context,
      initial: _filters,
      employeeNames: _isManagement ? _employeeNames : const [],
    );
    if (applied != null && mounted) _applyFilters(applied);
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasLeads;
  final bool canAddLead;
  final VoidCallback? onAddLead;
  const _EmptyState({
    required this.hasLeads,
    this.canAddLead = true,
    this.onAddLead,
  });

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: hasLeads
            ? Icons.search_off_rounded
            : (canAddLead
                ? Icons.add_location_alt_outlined
                : Icons.folder_open_outlined),
        title: hasLeads ? 'No matching leads' : 'No leads yet',
        message: hasLeads
            ? 'Try adjusting filters or search terms.'
            : (canAddLead
                ? 'Start by adding your first land lead.'
                : 'Leads added by employees will appear here.'),
        action: onAddLead == null
            ? null
            : PrimaryButton(
                label: hasLeads
                    ? 'Clear filters'
                    : (canAddLead ? 'Add Lead' : 'Clear filters'),
                icon: hasLeads
                    ? Icons.filter_alt_off
                    : (canAddLead ? Icons.add : Icons.filter_alt_off),
                onPressed: onAddLead,
              ),
      );
}

// ── Loading Skeleton ──────────────────────────────────────────────────────────

class _LeadsLoadingSkeleton extends StatelessWidget {
  const _LeadsLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, __) => const LoadingSkeleton(
              width: 156,
              height: 118,
              radius: AppColors.radiusMd,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const LoadingSkeleton(height: 48, radius: AppColors.radiusSm),
        const SizedBox(height: AppSpacing.md),
        Column(
          children: List.generate(
            6,
            (i) => Padding(
              padding: EdgeInsets.only(bottom: i < 5 ? 8 : 0),
              child: Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: context.fomraSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: context.fomraBorder.withValues(alpha: 0.75),
                  ),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LoadingSkeleton(height: 10, width: 56, radius: 4),
                          SizedBox(height: 6),
                          LoadingSkeleton(height: 14, width: 140, radius: 4),
                          SizedBox(height: 6),
                          LoadingSkeleton(height: 10, width: 200, radius: 4),
                        ],
                      ),
                    ),
                    SizedBox(width: 12),
                    LoadingSkeleton(height: 22, width: 72, radius: 999),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Summary strip ─────────────────────────────────────────────────────────────

class _LeadSummary extends StatelessWidget {
  final List<LandLead> leads;
  final void Function(LeadStatus? status, String title) onTapStatus;

  const _LeadSummary({
    required this.leads,
    required this.onTapStatus,
  });

  @override
  Widget build(BuildContext context) {
    final kpis = [
      (LeadStatus.negotiation, Icons.handshake_outlined),
      (LeadStatus.legal, Icons.gavel_outlined),
      (LeadStatus.signed, Icons.check_circle),
      (LeadStatus.dropped, Icons.cancel_outlined),
      (null, Icons.person_search_outlined),
    ];

    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kpis.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final status = kpis[i].$1;
          final icon = kpis[i].$2;
          final count = status == null
              ? leads.where((l) => l.status.isProspect).length
              : leads.where((l) => l.status == status).length;
          return LandWorkspaceStatusCard(
            statusName: status?.label ?? 'Prospect',
            subtitle: status == null ? 'Pipeline stage' : 'Leads',
            value: count,
            icon: icon,
            accent: status?.color ?? const Color(0xFF2563EB),
            onTap: () => onTapStatus(status, status?.label ?? 'Prospect'),
          );
        },
      ),
    );
  }
}

// ── Lead list row ─────────────────────────────────────────────────────────────

class _LeadListRow extends StatefulWidget {
  final LandLead lead;
  final bool isManagement;
  final VoidCallback? onTap;
  final VoidCallback? onView;
  final VoidCallback? onAssign;
  final VoidCallback? onScheduleMeeting;
  final VoidCallback? onViewMap;
  final VoidCallback? onEdit;
  final Future<bool> Function()? onDelete;
  final bool selectionMode;
  final bool selected;

  const _LeadListRow({
    required this.lead,
    this.isManagement = false,
    this.onTap,
    this.onView,
    this.onAssign,
    this.onScheduleMeeting,
    this.onViewMap,
    this.onEdit,
    this.onDelete,
    this.selectionMode = false,
    this.selected = false,
  });

  @override
  State<_LeadListRow> createState() => _LeadListRowState();
}

class _LeadListRowState extends State<_LeadListRow> {
  bool _hovered = false;

  bool get _hoverEnabled =>
      !widget.selectionMode && FomraLayout.isDesktop(context);

  String get _title => widget.lead.displayName;

  String get _locationText {
    final parts = <String>[];
    if (widget.lead.location.trim().isNotEmpty) {
      parts.add(widget.lead.location.trim());
    }
    if (widget.lead.village.trim().isNotEmpty) {
      parts.add(widget.lead.village.trim());
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final statusColor = _crmStatusColor(lead.status);
    final priorityColor = _leadPriorityColor(lead);
    final priorityLabel = _leadPriorityLabel(lead);
    final assignee = lead.createdByName.trim();
    // An executive only ever sees their own leads, so their own name on every
    // card is noise — hide it (management and RM/Head still see other people's).
    final me =
        (AuthService.instance.currentUser?.fullName ?? '').trim().toLowerCase();
    final showAssignee = assignee.isNotEmpty &&
        !(!AuthService.instance.isManagement &&
            assignee.toLowerCase() == me);
    final dateText =
        '${lead.addedOn.day}/${lead.addedOn.month}/${lead.addedOn.year}';
    final statusLabel = lead.status.isProspect
        ? lead.status.shortLabel
        : lead.status.label;
    final hoverActive = _hovered && _hoverEnabled;

    return MouseRegion(
      onEnter: _hoverEnabled ? (_) => setState(() => _hovered = true) : null,
      onExit: _hoverEnabled ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: AppMotion.slow,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: widget.selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : context.fomraSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hoverActive
                ? AppColors.primary.withValues(alpha: 0.45)
                : widget.selected
                    ? AppColors.primary.withValues(alpha: 0.28)
                    : context.fomraBorder.withValues(alpha: 0.8),
            width: hoverActive ? 1.5 : 1,
          ),
          boxShadow: context.fomraCardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.selectionMode) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 10),
                          child: AnimatedContainer(
                            duration: AppMotion.slow,
                            curve: AppMotion.curve,
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: widget.selected
                                  ? AppColors.primary
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.selected
                                    ? AppColors.primary
                                    : context.fomraBorder,
                                width: 2,
                              ),
                            ),
                            child: widget.selected
                                ? const Icon(Icons.check,
                                    size: 13, color: Colors.white)
                                : null,
                          ),
                        ),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                                color: context.fomraTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  '#${lead.leadId}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                    color: context.fomraTextSecondary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _LeadPriorityBadge(
                                  label: priorityLabel,
                                  color: priorityColor,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _LeadCompactMetaRow(
                              location: _locationText,
                              district: lead.district.trim(),
                              surveyNumber: lead.surveyNumber.trim(),
                              landExtent: lead.landExtent.trim(),
                              landType: lead.landType.label,
                              dateText: dateText,
                            ),
                            if (showAssignee) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 11,
                                    backgroundColor: AppColors.primary
                                        .withValues(alpha: 0.12),
                                    child: Text(
                                      _initialsFromName(assignee),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      assignee,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: context.fomraTextTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _CrmStatusChip(
                        label: statusLabel,
                        color: statusColor,
                      ),
                    ],
                  ),
                  AnimatedCrossFade(
                    duration: AppMotion.slow,
                    sizeCurve: AppMotion.curve,
                    firstCurve: AppMotion.curve,
                    secondCurve: AppMotion.curve,
                    crossFadeState: hoverActive
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity, height: 0),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _LeadHoverActions(
                        onView: widget.onView,
                        onAssign: widget.onAssign,
                        onScheduleMeeting: widget.onScheduleMeeting,
                        onViewMap: widget.onViewMap,
                        onEdit: widget.onEdit,
                        onDelete: widget.onDelete,
                      ),
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

class _LeadPriorityBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _LeadPriorityBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: color,
        ),
      ),
    );
  }
}

class _CrmStatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _CrmStatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _LeadCompactMetaRow extends StatelessWidget {
  final String location;
  final String district;
  final String surveyNumber;
  final String landExtent;
  final String landType;
  final String dateText;

  const _LeadCompactMetaRow({
    required this.location,
    required this.district,
    required this.surveyNumber,
    required this.landExtent,
    required this.landType,
    required this.dateText,
  });

  @override
  Widget build(BuildContext context) {
    final metaStyle = TextStyle(
      fontSize: 11,
      height: 1.25,
      fontWeight: FontWeight.w500,
      color: context.fomraTextSecondary,
    );
    final areaStyle = metaStyle.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      color: context.fomraTextPrimary,
    );

    Widget segment(Widget child) => Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Flexible(child: child)],
          ),
        );

    Widget bullet() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Text('•',
              style: TextStyle(
                  fontSize: 10, color: context.fomraTextTertiary)),
        );

    final wide = MediaQuery.sizeOf(context).width >= 720;

    if (!wide) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 0,
        runSpacing: 2,
        children: [
          if (location.isNotEmpty) ...[
            Icon(Icons.place_outlined,
                size: 12, color: context.fomraTextTertiary),
            const SizedBox(width: 3),
            Text(location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metaStyle),
          ],
          if (district.isNotEmpty) ...[
            const SizedBox(width: 6),
            _DistrictBadge(label: district),
          ],
          if (surveyNumber.isNotEmpty) ...[
            bullet(),
            Icon(Icons.tag_outlined,
                size: 12, color: context.fomraTextTertiary),
            const SizedBox(width: 3),
            Text('Svy $surveyNumber',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle),
          ],
          if (landExtent.isNotEmpty) ...[
            bullet(),
            Text(landExtent,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: areaStyle),
          ],
          if (landType.isNotEmpty) ...[
            bullet(),
            Text(landType,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle),
          ],
          bullet(),
          Icon(Icons.calendar_today_outlined,
              size: 11, color: context.fomraTextTertiary),
          const SizedBox(width: 3),
          Text(dateText, style: metaStyle),
        ],
      );
    }

    return Row(
      children: [
        if (location.isNotEmpty)
          segment(Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.place_outlined,
                  size: 12, color: context.fomraTextTertiary),
              const SizedBox(width: 3),
              Flexible(
                child: Text(location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: metaStyle),
              ),
            ],
          )),
        if (district.isNotEmpty) ...[
          const SizedBox(width: 6),
          _DistrictBadge(label: district),
        ],
        if (surveyNumber.isNotEmpty) ...[
          bullet(),
          segment(Text('Svy $surveyNumber',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle)),
        ],
        if (landExtent.isNotEmpty) ...[
          bullet(),
          segment(Text(landExtent,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: areaStyle)),
        ],
        if (landType.isNotEmpty) ...[
          bullet(),
          segment(Text(landType,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle)),
        ],
        bullet(),
        segment(Text(dateText, style: metaStyle)),
      ],
    );
  }
}

class _DistrictBadge extends StatelessWidget {
  final String label;
  const _DistrictBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: AppColors.info,
        ),
      ),
    );
  }
}

class _LeadHoverActions extends StatelessWidget {
  final VoidCallback? onView;
  final VoidCallback? onAssign;
  final VoidCallback? onScheduleMeeting;
  final VoidCallback? onViewMap;
  final VoidCallback? onEdit;
  final Future<bool> Function()? onDelete;

  const _LeadHoverActions({
    this.onView,
    this.onAssign,
    this.onScheduleMeeting,
    this.onViewMap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HoverActionButton(
          icon: Icons.visibility_outlined,
          label: 'View',
          onTap: onView,
        ),
        if (onAssign != null) ...[
          const SizedBox(width: 6),
          _HoverActionButton(
            icon: Icons.person_add_alt_1_outlined,
            label: 'Assign',
            onTap: onAssign,
          ),
        ],
        const SizedBox(width: 6),
        _HoverActionButton(
          icon: Icons.event_outlined,
          label: 'Meeting',
          onTap: onScheduleMeeting,
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'More',
          padding: EdgeInsets.zero,
          icon: Icon(Icons.more_horiz,
              size: 18, color: context.fomraTextSecondary),
          onSelected: (value) async {
            switch (value) {
              case 'map':
                onViewMap?.call();
              case 'edit':
                onEdit?.call();
              case 'delete':
                await onDelete?.call();
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'map', child: Text('View Map')),
            if (onEdit != null)
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (onDelete != null)
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: AppColors.error)),
              ),
          ],
        ),
      ],
    );
  }
}

class _HoverActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _HoverActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final list = parts.toList();
  if (list.isEmpty) return '?';
  if (list.length == 1) return list.first[0].toUpperCase();
  return '${list.first[0]}${list.last[0]}'.toUpperCase();
}

String _leadPriorityLabel(LandLead lead) {
  return switch (lead.status) {
    LeadStatus.signed => 'Low',
    LeadStatus.dropped => 'Low',
    LeadStatus.onHold => 'Low',
    LeadStatus.prospectMeetingCompleted => 'Medium',
    LeadStatus.legal => 'Medium',
    _ => 'High',
  };
}

Color _leadPriorityColor(LandLead lead) {
  return switch (lead.status) {
    LeadStatus.signed => AppColors.success,
    LeadStatus.dropped => AppColors.textSecondary,
    LeadStatus.onHold => AppColors.textSecondary,
    LeadStatus.prospectMeetingCompleted => AppColors.warning,
    LeadStatus.legal => AppColors.warning,
    _ => AppColors.error,
  };
}

Color _crmStatusColor(LeadStatus status) {
  return switch (status) {
    LeadStatus.signed => AppColors.success,
    LeadStatus.prospectMeetingCompleted => AppColors.success,
    LeadStatus.managementMeetingCompleted => AppColors.info,
    LeadStatus.prospectMeetingPending => AppColors.warning,
    LeadStatus.negotiation => AppColors.primary,
    LeadStatus.legal => AppColors.purple,
    LeadStatus.dropped => AppColors.error,
    LeadStatus.onHold => AppColors.textSecondary,
  };
}
