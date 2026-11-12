import 'package:flutter/material.dart';

import '../../models/land_lead.dart';
import '../../services/land_lead_service.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';

/// Editor for the pricing, risk/utility, multi-broker and pre-signing
/// milestone fields added in the 2026-08 Land Sourcing Module Review.
/// Deliberately kept separate from the main Add/Edit Lead form — this
/// writes through [LandLeadService.updateDealAndRiskDetails], which only
/// ever touches these specific columns.
class DealRiskDetailsDialog extends StatefulWidget {
  final LandLead lead;

  const DealRiskDetailsDialog({super.key, required this.lead});

  @override
  State<DealRiskDetailsDialog> createState() => _DealRiskDetailsDialogState();
}

class _DealRiskDetailsDialogState extends State<DealRiskDetailsDialog> {
  late final _askingCtrl = TextEditingController(
      text: _fmtNum(widget.lead.askingPrice));
  late final _expectedCtrl = TextEditingController(
      text: _fmtNum(widget.lead.expectedPrice));
  late final _guidelineCtrl = TextEditingController(
      text: _fmtNum(widget.lead.guidelineValue));
  late final _marketCtrl = TextEditingController(
      text: _fmtNum(widget.lead.marketValueEstimate));
  late final _restrictionsCtrl =
      TextEditingController(text: widget.lead.governmentRestrictions);
  late final _tokenAmountCtrl =
      TextEditingController(text: _fmtNum(widget.lead.tokenAdvanceAmount));
  late final _tokenNotesCtrl =
      TextEditingController(text: widget.lead.tokenAdvanceNotes);
  late final _agreementNotesCtrl =
      TextEditingController(text: widget.lead.agreementNotes);

  late String _litigation = widget.lead.litigationStatus;
  late String _encumbrance = widget.lead.encumbranceStatus;
  late String _water = widget.lead.waterAvailability;
  late String _electricity = widget.lead.electricityAvailability;
  late String _agreementStatus = widget.lead.agreementStatus;
  late DateTime? _tokenDate = widget.lead.tokenAdvanceDate;
  late DateTime? _agreementDate = widget.lead.agreementDate;

  late final List<TextEditingController> _brokerNameCtrls;
  late final List<TextEditingController> _brokerContactCtrls;

  bool _saving = false;

  static String _fmtNum(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');

  static double? _parseNum(String raw) {
    final t = raw.trim();
    return t.isEmpty ? null : double.tryParse(t);
  }

  @override
  void initState() {
    super.initState();
    final brokers = widget.lead.additionalBrokers;
    _brokerNameCtrls = [
      for (final b in brokers) TextEditingController(text: b.name),
    ];
    _brokerContactCtrls = [
      for (final b in brokers) TextEditingController(text: b.contact),
    ];
  }

  @override
  void dispose() {
    _askingCtrl.dispose();
    _expectedCtrl.dispose();
    _guidelineCtrl.dispose();
    _marketCtrl.dispose();
    _restrictionsCtrl.dispose();
    _tokenAmountCtrl.dispose();
    _tokenNotesCtrl.dispose();
    _agreementNotesCtrl.dispose();
    for (final c in _brokerNameCtrls) {
      c.dispose();
    }
    for (final c in _brokerContactCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addBroker() => setState(() {
        _brokerNameCtrls.add(TextEditingController());
        _brokerContactCtrls.add(TextEditingController());
      });

  void _removeBroker(int index) => setState(() {
        _brokerNameCtrls.removeAt(index).dispose();
        _brokerContactCtrls.removeAt(index).dispose();
      });

  Future<void> _pickDate(bool isToken) async {
    final initial = (isToken ? _tokenDate : _agreementDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isToken) {
        _tokenDate = picked;
      } else {
        _agreementDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final brokers = <OwnerContact>[
        for (var i = 0; i < _brokerNameCtrls.length; i++)
          if (_brokerNameCtrls[i].text.trim().isNotEmpty ||
              _brokerContactCtrls[i].text.trim().isNotEmpty)
            OwnerContact(
              name: _brokerNameCtrls[i].text.trim(),
              contact: _brokerContactCtrls[i].text.trim(),
            ),
      ];
      final updated = await LandLeadService.updateDealAndRiskDetails(
        leadId: widget.lead.leadId,
        previous: widget.lead,
        askingPrice: _parseNum(_askingCtrl.text),
        expectedPrice: _parseNum(_expectedCtrl.text),
        guidelineValue: _parseNum(_guidelineCtrl.text),
        marketValueEstimate: _parseNum(_marketCtrl.text),
        litigationStatus: _litigation,
        encumbranceStatus: _encumbrance,
        waterAvailability: _water,
        electricityAvailability: _electricity,
        governmentRestrictions: _restrictionsCtrl.text,
        additionalBrokers: brokers,
        tokenAdvanceAmount: _parseNum(_tokenAmountCtrl.text),
        tokenAdvanceDate: _tokenDate,
        tokenAdvanceNotes: _tokenNotesCtrl.text,
        agreementStatus: _agreementStatus,
        agreementDate: _agreementDate,
        agreementNotes: _agreementNotesCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.error(context, 'Could not save: $e');
    }
  }

  InputDecoration _dec(String label, {String? prefix}) => InputDecoration(
        labelText: label,
        prefixText: prefix,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: context.fomraTextSecondary,
          ),
        ),
      );

  Widget _statusDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: _dec(label),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(_labelize(o))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  static String _labelize(String raw) => raw
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: fomraDialogInset(context),
      backgroundColor: context.fomraSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints:
            fomraDialogConstraints(context, maxWidth: 520, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Deal & Risk Details',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('Pricing & Valuation (₹)'),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _askingCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: _dec('Asking price', prefix: '₹ '),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _expectedCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: _dec('Expected price', prefix: '₹ '),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _guidelineCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: _dec('Guideline value', prefix: '₹ '),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _marketCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                _dec('Market value estimate', prefix: '₹ '),
                          ),
                        ),
                      ]),
                      _sectionTitle('Risk & Utilities'),
                      Row(children: [
                        Expanded(
                          child: _statusDropdown(
                            'Litigation status',
                            _litigation,
                            const [
                              'unknown',
                              'none',
                              'suspected',
                              'confirmed',
                              'cleared'
                            ],
                            (v) => setState(() => _litigation = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statusDropdown(
                            'Encumbrance status',
                            _encumbrance,
                            const ['unknown', 'clear', 'encumbered', 'cleared'],
                            (v) => setState(() => _encumbrance = v),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: _statusDropdown(
                            'Water availability',
                            _water,
                            const ['unknown', 'available', 'not_available'],
                            (v) => setState(() => _water = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statusDropdown(
                            'Electricity availability',
                            _electricity,
                            const ['unknown', 'available', 'not_available'],
                            (v) => setState(() => _electricity = v),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _restrictionsCtrl,
                        maxLines: 2,
                        decoration: _dec(
                            'Government restrictions (CRZ, conversion pending, zoning notes...)'),
                      ),
                      _sectionTitle('Additional Brokers'),
                      for (var i = 0; i < _brokerNameCtrls.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Expanded(
                              child: TextFormField(
                                controller: _brokerNameCtrls[i],
                                decoration: _dec('Broker ${i + 2} name'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _brokerContactCtrls[i],
                                decoration: _dec('Contact'),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 20),
                              onPressed: () => _removeBroker(i),
                            ),
                          ]),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addBroker,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add broker'),
                        ),
                      ),
                      _sectionTitle('Token Advance'),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _tokenAmountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: _dec('Amount', prefix: '₹ '),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(true),
                            child: Text(_tokenDate == null
                                ? 'Pick date'
                                : '${_tokenDate!.day}/${_tokenDate!.month}/${_tokenDate!.year}'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _tokenNotesCtrl,
                        decoration: _dec('Notes'),
                      ),
                      _sectionTitle('Agreement'),
                      Row(children: [
                        Expanded(
                          child: _statusDropdown(
                            'Status',
                            _agreementStatus,
                            const [
                              'not_started',
                              'drafted',
                              'under_review',
                              'executed'
                            ],
                            (v) => setState(() => _agreementStatus = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(false),
                            child: Text(_agreementDate == null
                                ? 'Pick date'
                                : '${_agreementDate!.day}/${_agreementDate!.month}/${_agreementDate!.year}'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _agreementNotesCtrl,
                        decoration: _dec('Notes'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
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
