import 'package:flutter/material.dart';

import '../../models/employee_profile.dart';
import '../../services/app_store.dart';
import '../../services/employee_service.dart';
import '../../services/team_hierarchy.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/portal_page_layout.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/profile_avatar.dart';

/// "Manage Team": a Reporting Manager assigns Executives; a Head assigns
/// Reporting Managers (each expandable to its Executives). Uses the existing
/// employee roster + reports_to line — no new pages/routes.
class TeamManagementScreen extends StatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> {
  bool _loading = true;
  String _search = '';

  bool _matchesSearch(EmployeeProfile e) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return e.fullName.toLowerCase().contains(q) ||
        e.designation.toLowerCase().contains(q) ||
        e.email.toLowerCase().contains(q);
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final list = await EmployeeService.getAll();
      if (list.isNotEmpty) AppStore.instance.setEmployees(list);
    } catch (_) {/* keep whatever is cached */}
    if (mounted) setState(() => _loading = false);
  }

  EmployeeProfile? get _me => TeamHierarchy.currentProfile;

  Future<void> _assign(String employeeEmail, String managerEmail) async {
    try {
      await EmployeeService.assignReportsTo(employeeEmail, managerEmail);
      // assignReportsTo already updated the in-memory roster, so re-render from
      // it directly rather than re-fetch (which could momentarily lag).
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Open the searchable, multi-select picker and assign everyone chosen to
  /// [managerEmail]'s team.
  Future<void> _showAddSheet({
    required String title,
    required String emptyMessage,
    required List<EmployeeProfile> options,
    required String managerEmail,
  }) async {
    if (options.isEmpty) {
      AppFeedback.info(context, emptyMessage);
      return;
    }
    final picked = await showModalBottomSheet<List<EmployeeProfile>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.fomraSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _EmployeePickerSheet(title: title, options: options),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      for (final e in picked) {
        await EmployeeService.assignReportsTo(e.email, managerEmail);
      }
      if (!mounted) return;
      setState(() {});
      AppFeedback.success(
        context,
        picked.length == 1
            ? '${picked.first.fullName} added to your team'
            : '${picked.length} members added to your team',
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return FomraAppShell(
      currentRoute: '/home',
      backgroundColor: context.fomraPageBg,
      appBar: const FomraSubPageAppBar(title: 'Manage Team'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (me != null && (me.isReportingManager || me.isHead)) ...[
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Search by name, designation or email…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: context.fomraSurfaceVar,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (me == null)
                  const AppCard(
                    child: EmptyState(
                      icon: Icons.group_off_outlined,
                      title: 'Team management unavailable',
                      message:
                          'Your profile could not be found. Ask management to set your designation.',
                    ),
                  )
                else if (me.isReportingManager)
                  _reportingManagerView(me)
                else if (me.isHead)
                  _headView(me)
                else
                  const AppCard(
                    child: EmptyState(
                      icon: Icons.info_outline_rounded,
                      title: 'No team to manage',
                      message:
                          'Team management is available to Reporting Managers and Heads.',
                    ),
                  ),
              ],
            ),
    );
  }

  // ── Reporting Manager: assign executives ───────────────────────────────────
  Widget _reportingManagerView(EmployeeProfile me) {
    final execs = TeamHierarchy.executivesUnder(me.email);
    final visibleExecs = execs.where(_matchesSearch).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'My Executives',
          subtitle: '${execs.length} assigned',
          icon: Icons.groups_2_outlined,
          trailing: TextButton.icon(
            onPressed: () => _showAddSheet(
              title: 'Add executives',
              emptyMessage:
                  'No executives to add. Ask management to add employees with the Executive role.',
              options: TeamHierarchy.assignableExecutivesFor(me.email),
              managerEmail: me.email,
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Add'),
          ),
        ),
        const SizedBox(height: 12),
        if (execs.isEmpty)
          const AppCard(
            child: EmptyState(
              icon: Icons.person_search_outlined,
              title: 'No executives yet',
              message: 'Use Add to assign executives to your team.',
            ),
          )
        else if (visibleExecs.isEmpty)
          AppCard(
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matches',
              message: 'No one matches "$_search".',
            ),
          )
        else
          for (final e in visibleExecs) _memberTile(e, onRemove: () => _assign(e.email, '')),
      ],
    );
  }

  // ── Head: assign reporting managers, expand to executives ──────────────────
  Widget _headView(EmployeeProfile me) {
    final rms = TeamHierarchy.managersUnder(me.email);
    final searching = _search.trim().isNotEmpty;
    final visible = <MapEntry<EmployeeProfile, List<EmployeeProfile>>>[];
    for (final rm in rms) {
      final execs = TeamHierarchy.executivesUnder(rm.email);
      if (!searching) {
        visible.add(MapEntry(rm, execs));
        continue;
      }
      final managerMatches = _matchesSearch(rm);
      final matchingExecs = execs.where(_matchesSearch).toList();
      if (managerMatches || matchingExecs.isNotEmpty) {
        visible.add(MapEntry(rm, managerMatches ? execs : matchingExecs));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'My Reporting Managers',
          subtitle: '${rms.length} assigned',
          icon: Icons.supervisor_account_outlined,
          trailing: TextButton.icon(
            onPressed: () => _showAddSheet(
              title: 'Add reporting managers',
              emptyMessage:
                  'No reporting managers to add. Ask management to add employees with the Reporting Manager role.',
              options: TeamHierarchy.assignableManagersFor(me.email),
              managerEmail: me.email,
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Add'),
          ),
        ),
        const SizedBox(height: 12),
        if (rms.isEmpty)
          const AppCard(
            child: EmptyState(
              icon: Icons.person_search_outlined,
              title: 'No reporting managers yet',
              message: 'Use Add to assign reporting managers to your team.',
            ),
          )
        else if (visible.isEmpty)
          AppCard(
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matches',
              message: 'No one matches "$_search".',
            ),
          )
        else
          for (final entry in visible)
            _ManagerExpansionCard(
              key: ValueKey('${entry.key.email}-$searching'),
              manager: entry.key,
              executives: entry.value,
              onRemove: () => _assign(entry.key.email, ''),
              initiallyExpanded: searching,
            ),
      ],
    );
  }

  Widget _memberTile(EmployeeProfile e, {VoidCallback? onRemove}) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      radius: AppColors.radiusMd,
      interactive: false,
      child: Row(
        children: [
          ProfileAvatar(email: e.email, name: e.fullName, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.fullName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.fomraTextPrimary,
                  ),
                ),
                Text(
                  e.designation.isEmpty
                      ? EmployeeDesignations.executive
                      : e.designation,
                  style:
                      TextStyle(fontSize: 12, color: context.fomraTextSecondary),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove from team',
              onPressed: onRemove,
              icon: const Icon(Icons.person_remove_outlined, size: 20),
              color: AppColors.error,
            ),
        ],
      ),
    );
  }
}

/// Searchable, multi-select employee picker shown as a bottom sheet. Returns
/// the chosen employees (or null if cancelled).
class _EmployeePickerSheet extends StatefulWidget {
  final String title;
  final List<EmployeeProfile> options;

  const _EmployeePickerSheet({required this.title, required this.options});

  @override
  State<_EmployeePickerSheet> createState() => _EmployeePickerSheetState();
}

class _EmployeePickerSheetState extends State<_EmployeePickerSheet> {
  String _query = '';
  final _selected = <String>{}; // emails

  List<EmployeeProfile> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options
        .where((e) =>
            e.fullName.toLowerCase().contains(q) ||
            e.email.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    // Sheet grows with the keyboard and caps at ~80% height.
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.fomraBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: context.fomraTextPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${_selected.length} selected',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search by name or email…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: context.fomraSurfaceVar,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          'No matches for "$_query".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.fomraTextSecondary),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final e = filtered[i];
                          final checked = _selected.contains(e.email);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(e.email);
                              } else {
                                _selected.remove(e.email);
                              }
                            }),
                            controlAffinity: ListTileControlAffinity.trailing,
                            secondary: ProfileAvatar(
                              email: e.email,
                              name: e.fullName,
                              radius: 18,
                            ),
                            title: Text(e.fullName),
                            subtitle: Text(
                              TeamHierarchy.currentTeamLabel(e),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.fomraTextSecondary,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _selected.isEmpty
                            ? null
                            : () => Navigator.pop(
                                  context,
                                  widget.options
                                      .where((e) => _selected.contains(e.email))
                                      .toList(),
                                ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _selected.isEmpty
                              ? 'Add'
                              : 'Add ${_selected.length}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagerExpansionCard extends StatefulWidget {
  final EmployeeProfile manager;
  final List<EmployeeProfile> executives;
  final VoidCallback onRemove;
  final bool initiallyExpanded;

  const _ManagerExpansionCard({
    super.key,
    required this.manager,
    required this.executives,
    required this.onRemove,
    this.initiallyExpanded = false,
  });

  @override
  State<_ManagerExpansionCard> createState() => _ManagerExpansionCardState();
}

class _ManagerExpansionCardState extends State<_ManagerExpansionCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final execs = widget.executives;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.fomraSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.fomraBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ProfileAvatar(
                    email: widget.manager.email,
                    name: widget.manager.fullName,
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.manager.fullName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        Text(
                          'Reporting Manager · ${execs.length} executive${execs.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove from team',
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.person_remove_outlined, size: 20),
                    color: AppColors.error,
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: context.fomraTextSecondary),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (execs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'No executives assigned to this reporting manager.',
                  style: TextStyle(color: context.fomraTextSecondary),
                ),
              )
            else
              for (final e in execs)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: Row(
                    children: [
                      ProfileAvatar(
                          email: e.email, name: e.fullName, radius: 15),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.fullName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                      ),
                      Text(
                        'Executive',
                        style: TextStyle(
                            fontSize: 11, color: context.fomraTextSecondary),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
