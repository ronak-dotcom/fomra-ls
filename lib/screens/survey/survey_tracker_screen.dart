import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/land_lead.dart';
import '../../services/app_store.dart';
import '../../services/document_index_service.dart';
import '../../services/field_calendar_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../utils/legal_document_catalog.dart';
import '../../widgets/land_workspace_ui.dart';
import '../../widgets/lead_filter_bar.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';

import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_loader.dart';
import '../land_lead/lead_detail_screen.dart';

enum _SurveyFilter { all, scheduled, completed, pending }

/// Survey schedule, completion, and pending status.
class SurveyTrackerScreen extends StatefulWidget {
  const SurveyTrackerScreen({super.key});

  @override
  State<SurveyTrackerScreen> createState() => _SurveyTrackerScreenState();
}

class _SurveyTrackerScreenState extends State<SurveyTrackerScreen> {
  List<FieldCalendarEvent> _events = [];
  bool _loading = true;
  String _query = '';
  final LandWorkspaceFilters _leadFilters = LandWorkspaceFilters();
  _SurveyFilter _filter = _SurveyFilter.all;

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
    await DocumentIndexService.instance.ensureLoaded();
    final all = await FieldCalendarService.getAll();
    if (!mounted) return;
    setState(() {
      _events = all
          .where((e) => e.kind == FieldCalendarKind.survey)
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      _loading = false;
    });
  }

  bool _hasSurveyReport(String leadId) {
    return DocumentIndexService.instance.documents.any((d) =>
        d.leadId == leadId &&
        LegalDocumentCatalog.classify(d.fileName) ==
            LegalDocCategory.surveyReport);
  }

  FieldCalendarEvent? _eventFor(String leadId) {
    final matches = _events.where((e) => e.leadId == leadId).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return matches.first;
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
    final ev = _eventFor(lead.leadId);
    final report = _hasSurveyReport(lead.leadId);
    final completed = (ev?.completed ?? false) || report;
    final scheduled = ev != null && !completed;
    final pending = !completed && ev == null;
    return switch (_filter) {
      _SurveyFilter.all =>
        lead.surveyNumber.trim().isNotEmpty || ev != null || report,
      _SurveyFilter.scheduled => scheduled,
      _SurveyFilter.completed => completed,
      _SurveyFilter.pending => pending && lead.surveyNumber.trim().isNotEmpty,
    };
  }

  Future<void> _scheduleSurvey(LandLead lead) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (time == null || !mounted) return;
    final at = DateTime(
      picked.year,
      picked.month,
      picked.day,
      time.hour,
      time.minute,
    );
    await FieldCalendarService.add(
      kind: FieldCalendarKind.survey,
      leadId: lead.leadId,
      title: 'Survey · ${lead.ownerName.isEmpty ? lead.leadId : lead.ownerName}',
      scheduledAt: at,
      reminderEnabled: true,
      remindMinutesBefore: 60,
    );
    await _load();
    if (mounted) {
      AppFeedback.success(context, 'Survey scheduled with reminder');
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy · hh:mm a');
    final leads = AppStore.instance.visibleLeads.where(_matches).toList();
    final scheduled = _events.where((e) => !e.completed).length;
    final completed = AppStore.instance.visibleLeads
        .where((l) =>
            (_eventFor(l.leadId)?.completed ?? false) ||
            _hasSurveyReport(l.leadId))
        .length;
    final pending = AppStore.instance.visibleLeads
        .where((l) =>
            l.surveyNumber.trim().isNotEmpty &&
            !(_eventFor(l.leadId)?.completed ?? false) &&
            !_hasSurveyReport(l.leadId) &&
            _eventFor(l.leadId) == null)
        .length;

    return FomraAppShell(
      currentRoute: '/survey-tracker',
      appBar: const FomraAppBar(
        moduleName: 'Survey Tracker',

      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: FomraLayout.pagePadding(context),
          children: [
            Text(
              'Survey Tracker',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: context.fomraTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Schedule · Completion · Pending status',
              style: TextStyle(fontSize: 13, color: context.fomraTextSecondary),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _kpi('Scheduled', '$scheduled', AppColors.info),
                _kpi('Completed', '$completed', AppColors.success),
                _kpi('Pending', '$pending', AppColors.warning),
              ],
            ),
            const SizedBox(height: 12),
            LeadFilterBar(
              filters: _leadFilters,
              onChanged: () => setState(() {}),
              onSearch: (v) => setState(() => _query = v),
              hintText: 'Search survey / owner…',
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _SurveyFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (f) {
                          _SurveyFilter.all => 'All',
                          _SurveyFilter.scheduled => 'Scheduled',
                          _SurveyFilter.completed => 'Completed',
                          _SurveyFilter.pending => 'Pending',
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
                child: AppLoader.center(message: 'Loading surveys…'),
              )
            else if (leads.isEmpty)
              const AppCard(
                child: EmptyState(
                  title: 'No survey items',
                  message:
                      'Leads with survey numbers appear here. Schedule surveys from a card.',
                ),
              )
            else
              ...leads.map((lead) {
                final ev = _eventFor(lead.leadId);
                final report = _hasSurveyReport(lead.leadId);
                final done = (ev?.completed ?? false) || report;
                final status = done
                    ? 'Completed'
                    : ev != null
                        ? 'Scheduled'
                        : 'Pending';
                final color = done
                    ? AppColors.success
                    : ev != null
                        ? AppColors.info
                        : AppColors.warning;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lead.displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: context.fomraTextPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (lead.surveyNumber.isNotEmpty)
                              'Sy ${lead.surveyNumber}',
                            if (lead.village.isNotEmpty) lead.village,
                            if (ev != null) df.format(ev.scheduledAt),
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LeadDetailScreen(lead: lead),
                                ),
                              ),
                              child: const Text('Open lead'),
                            ),
                            if (!done)
                              TextButton(
                                onPressed: () => _scheduleSurvey(lead),
                                child: Text(
                                  ev == null ? 'Schedule' : 'Reschedule',
                                ),
                              ),
                            if (ev != null && !ev.completed)
                              TextButton(
                                onPressed: () async {
                                  await FieldCalendarService.markCompleted(
                                      ev.id);
                                  await _load();
                                },
                                child: const Text('Mark complete'),
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
}
