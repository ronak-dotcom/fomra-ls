import 'package:flutter/material.dart';

import '../models/employee_profile.dart';
import '../models/land_lead.dart';
import '../services/app_store.dart';
import '../services/auth_service.dart';
import '../services/lead_review_service.dart';
import 'land_workspace_ui.dart';

/// The Land Workspace search + Filters button + active-filter chips, for any
/// screen that lists leads. Opens the same filter panel (status, land type,
/// source, location, broker, acres, pending, property review, dates), so a
/// filter means the same thing on every screen.
///
/// The screen owns [filters] and applies them with `filters.matches(lead)`;
/// this widget mutates [filters] and calls [onChanged] to rebuild. Mounting it
/// also loads the review index the Property Review filter reads.
class LeadFilterBar extends StatefulWidget {
  final LandWorkspaceFilters filters;
  final VoidCallback onChanged;
  final ValueChanged<String> onSearch;
  final String hintText;
  final bool showLeadSource;
  final bool showPendingStatus;
  final bool showReviewStatus;

  const LeadFilterBar({
    super.key,
    required this.filters,
    required this.onChanged,
    required this.onSearch,
    this.hintText = 'Search by owner, survey number, location...',
    this.showLeadSource = true,
    this.showPendingStatus = true,
    this.showReviewStatus = true,
  });

  @override
  State<LeadFilterBar> createState() => _LeadFilterBarState();
}

class _LeadFilterBarState extends State<LeadFilterBar> {
  @override
  void initState() {
    super.initState();
    LeadReviewIndex.instance.addListener(_onReviewsChanged);
    LeadReviewIndex.instance.ensureLoaded();
  }

  @override
  void dispose() {
    LeadReviewIndex.instance.removeListener(_onReviewsChanged);
    super.dispose();
  }

  // Review data arriving can change which leads a review filter keeps.
  void _onReviewsChanged() {
    if (widget.filters.reviewStatus != null) widget.onChanged();
  }

  Future<void> _open() async {
    final employeeNames = AuthService.instance.isManagement
        ? AppStore.instance.employees
            .where((e) => e.status == EmployeeStatus.active)
            .map((e) => e.fullName)
            .toList()
        : const <String>[];
    final applied = await showLandWorkspaceFilterPanel(
      context: context,
      initial: widget.filters,
      employeeNames: employeeNames,
      showLeadSource: widget.showLeadSource,
      showPendingStatus: widget.showPendingStatus,
      showReviewStatus: widget.showReviewStatus,
    );
    if (applied == null || !mounted) return;
    widget.filters.assignFrom(applied);
    widget.onChanged();
  }

  void _clearAll() {
    widget.filters.clear();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LandWorkspaceSearchBar(
          onChanged: widget.onSearch,
          activeFilterCount: widget.filters.activeCount,
          onFilterTap: _open,
          hintText: widget.hintText,
        ),
        if (widget.filters.hasActive) ...[
          const SizedBox(height: 10),
          LandWorkspaceActiveFilterChips(
            filters: widget.filters,
            onChanged: widget.onChanged,
            onClearAll: _clearAll,
          ),
        ],
      ],
    );
  }
}

/// Free-text match used by lead lists that adopt [LeadFilterBar].
bool leadMatchesSearch(LandLead l, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return '${l.leadId} ${l.displayName} ${l.ownerName} ${l.location} '
          '${l.village} ${l.taluk} ${l.district} ${l.surveyNumber} '
          '${l.brokerName} ${l.createdByName}'
      .toLowerCase()
      .contains(q);
}
