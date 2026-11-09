import 'package:flutter/material.dart';

import '../../models/land_lead.dart';
import '../../services/app_store.dart';
import '../../services/legal_verification_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/land_workspace_ui.dart';
import '../../widgets/lead_filter_bar.dart';
import '../../widgets/fomra_app_shell.dart';

// ── Main Screen ───────────────────────────────────────────────────────────────

class LegalVerificationScreen extends StatefulWidget {
  final bool isTab;
  const LegalVerificationScreen({super.key, this.isTab = false});

  @override
  State<LegalVerificationScreen> createState() =>
      _LegalVerificationScreenState();
}

class _LegalVerificationScreenState extends State<LegalVerificationScreen> {
  LandLead? _selectedLead;
  String _search = '';
  final LandWorkspaceFilters _leadFilters = LandWorkspaceFilters();

  // Legal Review fields
  final _ownershipCtrl       = TextEditingController();
  String _mortgageAnswer     = '';
  final _mortgageReasonCtrl  = TextEditingController();
  String _courtAnswer        = '';
  final _courtReasonCtrl     = TextEditingController();
  String _govtRiskAnswer     = '';
  final _govtRiskReasonCtrl  = TextEditingController();
  final _titleChainCtrl      = TextEditingController();
  final _encumbrancesCtrl    = TextEditingController();
  final _docValidityCtrl     = TextEditingController();
  String _legalResult        = '';
  final _legalResultNotesCtrl = TextEditingController();

  final Map<String, Map<String, dynamic>> _loadedReviews = {};
  bool _reviewSaving = false;

  @override
  void initState() {
    super.initState();
    AppStore.instance.addListener(_onStoreUpdate);
    _loadAllLegalData();
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_onStoreUpdate);
    _ownershipCtrl.dispose();
    _mortgageReasonCtrl.dispose();
    _courtReasonCtrl.dispose();
    _govtRiskReasonCtrl.dispose();
    _titleChainCtrl.dispose();
    _encumbrancesCtrl.dispose();
    _docValidityCtrl.dispose();
    _legalResultNotesCtrl.dispose();
    super.dispose();
  }

  void _onStoreUpdate() => setState(() {});

  List<LandLead> get _leads => AppStore.instance.visibleLeads;

  Future<void> _loadAllLegalData() async {
    try {
      final rows = await LegalVerificationService.getAll();
      if (!mounted) return;
      setState(() {
        for (final row in rows) {
          _loadedReviews[row['lead_id'] as String] = row;
        }
      });
    } catch (_) {}
  }

  void _openLead(LandLead lead) {
    setState(() {
      _selectedLead = lead;
      final row = _loadedReviews[lead.leadId];
      if (row != null) {
        _ownershipCtrl.text        = row['ownership']          as String? ?? '';
        _mortgageAnswer            = row['mortgage']           as String? ?? '';
        _mortgageReasonCtrl.text   = row['mortgage_reason']    as String? ?? '';
        _courtAnswer               = row['court_cases']        as String? ?? '';
        _courtReasonCtrl.text      = row['court_reason']       as String? ?? '';
        _govtRiskAnswer            = row['govt_risk']          as String? ?? '';
        _govtRiskReasonCtrl.text   = row['govt_risk_reason']   as String? ?? '';
        _titleChainCtrl.text       = row['title_chain']        as String? ?? '';
        _encumbrancesCtrl.text     = row['encumbrances']       as String? ?? '';
        _docValidityCtrl.text      = row['doc_validity']       as String? ?? '';
        _legalResult               = row['legal_result']       as String? ?? '';
        _legalResultNotesCtrl.text = row['legal_result_notes'] as String? ?? '';
      } else {
        _clearFields();
      }
    });
  }

  void _closeLead() => setState(() => _selectedLead = null);

  void _clearFields() {
    _ownershipCtrl.clear();
    _mortgageAnswer = '';
    _mortgageReasonCtrl.clear();
    _courtAnswer = '';
    _courtReasonCtrl.clear();
    _govtRiskAnswer = '';
    _govtRiskReasonCtrl.clear();
    _titleChainCtrl.clear();
    _encumbrancesCtrl.clear();
    _docValidityCtrl.clear();
    _legalResult = '';
    _legalResultNotesCtrl.clear();
  }

  Future<void> _saveReview() async {
    final lead = _selectedLead;
    if (lead == null) return;
    setState(() => _reviewSaving = true);
    try {
      final data = {
        'ownership':          _ownershipCtrl.text.trim(),
        'mortgage':           _mortgageAnswer,
        'mortgage_reason':    _mortgageReasonCtrl.text.trim(),
        'court_cases':        _courtAnswer,
        'court_reason':       _courtReasonCtrl.text.trim(),
        'govt_risk':          _govtRiskAnswer,
        'govt_risk_reason':   _govtRiskReasonCtrl.text.trim(),
        'title_chain':        _titleChainCtrl.text.trim(),
        'encumbrances':       _encumbrancesCtrl.text.trim(),
        'doc_validity':       _docValidityCtrl.text.trim(),
        'legal_result':       _legalResult,
        'legal_result_notes': _legalResultNotesCtrl.text.trim(),
      };
      await LegalVerificationService.save(lead.leadId, data);
      _loadedReviews[lead.leadId] = {'lead_id': lead.leadId, ...data};
      if (mounted) {
        AppFeedback.success(context, 'Legal review saved.');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Save failed: $e',
            duration: const Duration(seconds: 5));
      }
    } finally {
      if (mounted) setState(() => _reviewSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _selectedLead == null ? _buildLeadList() : _buildForm();
    if (widget.isTab) return Scaffold(body: body);
    return FomraAppShell(
      currentRoute: '/legal-verification',
      appBar: const FomraAppBar(moduleName: 'Legal Verification'),
      body: body,
    );
  }

  // ── Lead List ─────────────────────────────────────────────────────────────

  Widget _buildLeadList() {
    if (_leads.isEmpty) {
      return const EmptyState(
        icon: Icons.gavel_outlined,
        title: 'No leads found',
        message: 'Add leads in LandWorkspace first, then run legal review here.',
      );
    }

    final leads = _leads
        .where((l) => _leadFilters.matches(l) && leadMatchesSearch(l, _search))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: LeadFilterBar(
            filters: _leadFilters,
            onChanged: () => setState(() {}),
            onSearch: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: leads.isEmpty
              ? const EmptyState(
                  icon: Icons.filter_alt_off,
                  title: 'No leads match',
                  message: 'Try a different search or clear the filters.',
                )
              : _leadListView(leads),
        ),
      ],
    );
  }

  Widget _leadListView(List<LandLead> leads) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: leads.length,
      itemBuilder: (_, i) {
        final lead = leads[i];
        final result = _loadedReviews[lead.leadId]?['legal_result'] as String? ?? '';
        return GestureDetector(
          onTap: () => _openLead(lead),
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.gavel_outlined,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lead.ownerName.isNotEmpty
                              ? lead.ownerName
                              : lead.leadId,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text('${lead.leadId}  •  ${lead.location}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis),
                        if (result.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _resultChip(result),
                        ],
                      ]),
                ),
                const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary, size: 20),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _resultChip(String result) {
    final color = switch (result) {
      'CLEAR'       => const Color(0xFF16A34A),
      'OBSERVATION' => const Color(0xFFD97706),
      'HIGH RISK'   => const Color(0xFFDC2626),
      'REJECT'      => const Color(0xFF7C3AED),
      _             => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(result,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ── Legal Review Form ─────────────────────────────────────────────────────

  Widget _buildForm() {
    final lead = _selectedLead!;
    return Column(children: [
      // Back header
      Container(
        color: AppColors.primary,
        padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _closeLead,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lead.ownerName.isNotEmpty ? lead.ownerName : lead.leadId,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${lead.leadId}  •  ${lead.location}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
          ),
        ]),
      ),

      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Check', Icons.fact_check_outlined),
                const SizedBox(height: 14),

                _fillField('Ownership', _ownershipCtrl,
                    hint: 'Enter ownership details'),
                const SizedBox(height: 10),

                _yesNoField(
                  label: 'Mortgage',
                  answer: _mortgageAnswer,
                  reasonCtrl: _mortgageReasonCtrl,
                  onChanged: (v) => setState(() => _mortgageAnswer = v),
                ),
                const SizedBox(height: 10),

                _yesNoField(
                  label: 'Court Cases',
                  answer: _courtAnswer,
                  reasonCtrl: _courtReasonCtrl,
                  onChanged: (v) => setState(() => _courtAnswer = v),
                ),
                const SizedBox(height: 10),

                _yesNoField(
                  label: 'Government Acquisition Risk',
                  answer: _govtRiskAnswer,
                  reasonCtrl: _govtRiskReasonCtrl,
                  onChanged: (v) => setState(() => _govtRiskAnswer = v),
                ),
                const SizedBox(height: 10),

                _fillField('Title Chain', _titleChainCtrl,
                    hint: 'Describe title chain details'),
                const SizedBox(height: 10),

                _fillField('Encumbrances', _encumbrancesCtrl,
                    hint: 'List any encumbrances'),
                const SizedBox(height: 10),

                _fillField('Document Validity', _docValidityCtrl,
                    hint: 'Describe document validity'),
                const SizedBox(height: 24),

                _sectionHeader('Legal Result', Icons.verified_outlined),
                const SizedBox(height: 14),
                _resultPicker(),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _reviewSaving ? null : _saveReview,
                    icon: _reviewSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(
                        _reviewSaving ? 'Saving…' : 'Save Legal Review',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusSm)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ]),
        ),
      ),
    ]);
  }

  Widget _sectionHeader(String title, IconData icon) => Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ]);

  Widget _fillField(String label, TextEditingController ctrl,
          {String hint = ''}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.fomraBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.fomraBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: context.fomraSurfaceVar,
          ),
          style: const TextStyle(fontSize: 13),
        ),
      ]);

  Widget _yesNoField({
    required String label,
    required String answer,
    required TextEditingController reasonCtrl,
    required void Function(String) onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.fomraSurfaceVar,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.fomraBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Row(children: [
            _yesNoChip('Yes', answer == 'Yes', const Color(0xFFDC2626), onChanged),
            const SizedBox(width: 8),
            _yesNoChip('No', answer == 'No', AppColors.success, onChanged),
          ]),
          if (answer == 'Yes') ...[
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Enter reason...',
                hintStyle: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.fomraBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.fomraBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppColors.primary, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                filled: true,
                fillColor: context.fomraSurface,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ]),
      );

  Widget _yesNoChip(String label, bool selected, Color color,
          void Function(String) onTap) =>
      GestureDetector(
        onTap: () => onTap(selected ? '' : label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : context.fomraSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : context.fomraBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? color : AppColors.textSecondary)),
        ),
      );

  Widget _resultPicker() {
    const results = [
      ('CLEAR',       Color(0xFF16A34A), Icons.check_circle_outline),
      ('OBSERVATION', Color(0xFFD97706), Icons.remove_red_eye_outlined),
      ('HIGH RISK',   Color(0xFFDC2626), Icons.warning_amber_outlined),
      ('REJECT',      Color(0xFF7C3AED), Icons.cancel_outlined),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: results.map((r) {
          final (label, color, icon) = r;
          final selected = _legalResult == label;
          return GestureDetector(
            onTap: () => setState(() => _legalResult = selected ? '' : label),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.1)
                    : context.fomraSurfaceVar,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? color : context.fomraBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon,
                    color: selected ? color : context.fomraTextTertiary, size: 18),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? color : AppColors.textSecondary)),
              ]),
            ),
          );
        }).toList(),
      ),
      if (_legalResult.isNotEmpty) ...[
        const SizedBox(height: 14),
        TextField(
          controller: _legalResultNotesCtrl,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: 'Notes / Remarks',
            labelStyle: const TextStyle(fontSize: 13),
            hintText: 'Enter detailed remarks for this result...',
            hintStyle: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.fomraBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.fomraBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: AppColors.primary, width: 1.5)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: context.fomraSurfaceVar,
          ),
          style: const TextStyle(fontSize: 13),
        ),
      ],
    ]);
  }
}
