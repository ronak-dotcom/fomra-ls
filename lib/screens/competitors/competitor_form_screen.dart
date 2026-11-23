import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../models/competitor_project.dart';
import '../../services/competitor_service.dart';
import '../../services/gps_verification_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/image_compressor.dart';
import '../../utils/maps_link_pin.dart';
import '../../utils/maps_navigation.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_form.dart';

/// Add (quick: the essentials first, the rest under "More details") or edit
/// a competitor project. Returns the saved project.
class CompetitorFormScreen extends StatefulWidget {
  final CompetitorProject? existing;

  /// Link the new project to this lead when saved (added from a lead page).
  final String? linkLeadId;

  /// Village to start with (added from a lead page).
  final String? initialVillage;

  const CompetitorFormScreen({
    super.key,
    this.existing,
    this.linkLeadId,
    this.initialVillage,
  });

  static Future<CompetitorProject?> open(
    BuildContext context, {
    CompetitorProject? existing,
    String? linkLeadId,
    String? initialVillage,
  }) =>
      Navigator.of(context).push<CompetitorProject>(MaterialPageRoute(
        builder: (_) => CompetitorFormScreen(
          existing: existing,
          linkLeadId: linkLeadId,
          initialVillage: initialVillage,
        ),
      ));

  @override
  State<CompetitorFormScreen> createState() => _CompetitorFormScreenState();
}

class _PhaseDraft {
  final String id;
  final TextEditingController label;
  final TextEditingController plots;
  final TextEditingController sold;
  final TextEditingController left;
  final TextEditingController minSqft;
  final TextEditingController maxSqft;
  DateTime? launch;

  _PhaseDraft({CompetitorPhase? from, String defaultLabel = 'Phase 1'})
      : id = from?.id ?? '',
        label = TextEditingController(text: from?.label ?? defaultLabel),
        plots = TextEditingController(text: _n(from?.plots)),
        sold = TextEditingController(text: _n(from?.sold)),
        left = TextEditingController(text: _n(from?.available)),
        minSqft = TextEditingController(text: _n(from?.minPlotSqft)),
        maxSqft = TextEditingController(text: _n(from?.maxPlotSqft)),
        launch = from?.launchDate;

  bool get isEmpty =>
      plots.text.trim().isEmpty &&
      sold.text.trim().isEmpty &&
      left.text.trim().isEmpty &&
      minSqft.text.trim().isEmpty &&
      maxSqft.text.trim().isEmpty &&
      launch == null;

  CompetitorPhase toPhase() => CompetitorPhase(
        id: id,
        label: label.text.trim(),
        launchDate: launch,
        plots: _int(plots.text),
        sold: _int(sold.text),
        available: _int(left.text),
        minPlotSqft: _int(minSqft.text),
        maxPlotSqft: _int(maxSqft.text),
      );

  void dispose() {
    for (final c in [label, plots, sold, left, minSqft, maxSqft]) {
      c.dispose();
    }
  }
}

class _ContactDraft {
  final String id;
  final TextEditingController name;
  final TextEditingController phone;
  CompetitorContactRole role;
  bool isMain;

  _ContactDraft({CompetitorContact? from, this.isMain = false})
      : id = from?.id ?? '',
        name = TextEditingController(text: from?.name ?? ''),
        phone = TextEditingController(text: from?.phone ?? ''),
        role = from?.role ?? CompetitorContactRole.sales {
    if (from != null) isMain = from.isMain;
  }

  CompetitorContact toContact() => CompetitorContact(
        id: id,
        name: name.text.trim(),
        phone: phone.text.trim(),
        role: role,
        isMain: isMain,
      );

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

String _n(num? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.round().toString() : v.toString();
}

double? _num(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'[,₹\s]'), ''));

int? _int(String s) => _num(s)?.round();

class _CompetitorFormScreenState extends State<CompetitorFormScreen> {
  late final CompetitorProject? _e = widget.existing;
  bool get _isEdit => _e != null;

  late final _name = TextEditingController(text: _e?.name ?? '');
  late final _builder = TextEditingController(text: _e?.builder ?? '');
  late CompetitorType _type = _e?.type ?? CompetitorType.layout;
  late CompetitorStage _stage = _e?.stage ?? CompetitorStage.ongoing;
  late final _village =
      TextEditingController(text: _e?.village ?? widget.initialVillage ?? '');
  late final _taluk = TextEditingController(text: _e?.taluk ?? '');
  late final _district = TextEditingController(text: _e?.district ?? '');
  late final _mapsLink = TextEditingController(text: _e?.mapsLink ?? '');
  late LatLng? _pin = _e?.point;
  late String _gpsNote = _e?.gpsNote ?? '';
  late final _extent = TextEditingController(text: _n(_e?.extentAcres));
  late final _minSqft = TextEditingController(text: _n(_e?.minPlotSqft));
  late final _maxSqft = TextEditingController(text: _n(_e?.maxPlotSqft));
  late final _pre = TextEditingController(text: _n(_e?.preLaunchPrice));
  late final _quoted = TextEditingController(text: _n(_e?.quotedPrice));
  late final _negotiated = TextEditingController(text: _n(_e?.negotiatedPrice));
  late final _plcCorner = TextEditingController(text: _n(_e?.plcCorner));
  late final _plcFacing = TextEditingController(text: _n(_e?.plcFacing));
  late final _plcRoad = TextEditingController(text: _n(_e?.plcRoad));
  late final _road = TextEditingController(text: _n(_e?.mainRoadFt));
  late final _glv = TextEditingController(text: _n(_e?.glv));
  late final _authority = TextEditingController(text: _e?.approvalAuthority ?? '');
  late final _approvalNo = TextEditingController(text: _e?.approvalNo ?? '');
  late final _rera = TextEditingController(text: _e?.reraNo ?? '');
  late final _docs = TextEditingController(text: _n(_e?.documentationCharges));
  late final _maintenance = TextEditingController(text: _n(_e?.maintenanceCharge));
  late final _corpus = TextEditingController(text: _n(_e?.corpus));
  late final _otherCharges = TextEditingController(text: _e?.otherCharges ?? '');
  late final List<_ContactDraft> _contacts = [
    if (_e != null && _e.allContacts.isNotEmpty)
      for (final c in _e.allContacts) _ContactDraft(from: c)
    else
      _ContactDraft(isMain: true),
  ];
  late final _amenities = TextEditingController(text: _e?.amenities ?? '');
  late final _notes = TextEditingController(text: _e?.notes ?? '');
  late DateTime? _launch = _e?.launchDate;
  late final List<_PhaseDraft> _phases = [
    if (_e != null && _e.phases.isNotEmpty)
      for (final p in _e.phases) _PhaseDraft(from: p)
    else
      _PhaseDraft(),
  ];

  late bool _more = _isEdit;
  bool _saving = false;
  bool _locating = false;
  bool _readingLink = false;
  Uint8List? _photo;
  String _photoName = 'photo.jpg';

  @override
  void dispose() {
    for (final c in [
      _name, _builder, _village, _taluk, _district, _mapsLink, _extent,
      _minSqft, _maxSqft, _pre, _quoted, _negotiated, _plcCorner, _plcFacing,
      _plcRoad, _road, _glv, _authority, _approvalNo, _rera, _docs,
      _maintenance, _corpus, _otherCharges, _amenities, _notes,
    ]) {
      c.dispose();
    }
    for (final p in _phases) {
      p.dispose();
    }
    for (final c in _contacts) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final fix = await GpsVerificationService.captureLive();
      if (!mounted) return;
      setState(() {
        _pin = fix.point;
        _gpsNote = 'live GPS ±${fix.accuracyMeters.toStringAsFixed(0)} m';
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _readLink() async {
    final text = _mapsLink.text.trim();
    if (text.isEmpty) return;
    setState(() => _readingLink = true);
    try {
      final pin = await resolvePin(text);
      if (!mounted) return;
      setState(() {
        _pin = pin;
        _gpsNote = 'maps link';
      });
      AppFeedback.success(context, 'Pin set from the link.');
    } catch (e) {
      if (mounted) {
        AppFeedback.error(
            context, e.toString().replaceFirst(RegExp(r'^\w*Exception: '), ''));
      }
    } finally {
      if (mounted) setState(() => _readingLink = false);
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, maxWidth: 2400, imageQuality: 90);
      if (picked == null) return;
      final bytes = await ImageCompressor.compressTo250Kb(await picked.readAsBytes());
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _photoName = picked.name;
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, e.toString());
    }
  }

  Future<DateTime?> _pickDate(DateTime? current) => showDatePicker(
        context: context,
        initialDate: current ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(DateTime.now().year + 5),
      );

  CompetitorProject _build() {
    final e = _e;
    return CompetitorProject(
      id: e?.id ?? '',
      code: e?.code ?? '',
      name: _name.text.trim(),
      builder: _builder.text.trim(),
      type: _type,
      stage: _stage,
      village: _village.text.trim(),
      taluk: _taluk.text.trim(),
      district: _district.text.trim(),
      lat: _pin?.latitude,
      lng: _pin?.longitude,
      gpsNote: _pin == null ? '' : _gpsNote,
      mapsLink: _mapsLink.text.trim(),
      extentAcres: _num(_extent.text),
      approvalAuthority: _authority.text.trim(),
      approvalNo: _approvalNo.text.trim(),
      reraNo: _rera.text.trim(),
      mainRoadFt: _num(_road.text),
      minPlotSqft: _int(_minSqft.text),
      maxPlotSqft: _int(_maxSqft.text),
      preLaunchPrice: _num(_pre.text),
      quotedPrice: _num(_quoted.text),
      negotiatedPrice: _num(_negotiated.text),
      plcCorner: _num(_plcCorner.text),
      plcFacing: _num(_plcFacing.text),
      plcRoad: _num(_plcRoad.text),
      glv: _num(_glv.text),
      documentationCharges: _num(_docs.text),
      maintenanceCharge: _num(_maintenance.text),
      corpus: _num(_corpus.text),
      otherCharges: _otherCharges.text.trim(),
      amenities: _amenities.text.trim(),
      launchDate: _launch,
      notes: _notes.text.trim(),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppFeedback.warning(context, 'Type the project name.');
      return;
    }
    if (!_isEdit) {
      final key = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final same = CompetitorService.instance.all.where((p) =>
          p.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == key);
      if (same.isNotEmpty) {
        final p = same.first;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Already added?'),
            content: Text('${p.code} ${p.name}'
                '${p.builder.isEmpty ? '' : ' by ${p.builder}'} is already in '
                'the list. Add another project with this name?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Add anyway')),
            ],
          ),
        );
        if (go != true || !mounted) return;
      }
    }
    // A blank new phase row is left out; saved phases stay even when blank.
    final phases = [
      for (final d in _phases)
        if (!d.isEmpty || d.id.isNotEmpty) d.toPhase(),
    ];
    setState(() => _saving = true);
    try {
      final svc = CompetitorService.instance;
      final contacts = [for (final c in _contacts) c.toContact()];
      final saved = _isEdit
          ? await svc.update(_build(), phases: phases, contacts: contacts)
          : await svc.create(
              _build(),
              phases: phases,
              contacts: contacts,
              linkLeadId: widget.linkLeadId,
              photo: _photo,
              photoName: _photoName,
            );
      if (!mounted) return;
      AppFeedback.success(
          context, _isEdit ? 'Saved ${saved.code}.' : 'Added ${saved.code} ${saved.name}.');
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppFeedback.error(context, 'Could not save: $e');
      }
    }
  }

  // ── Fields ─────────────────────────────────────────────────────────────

  Widget _text(TextEditingController c, String label,
          {String? hint, int maxLines = 1, TextInputType? keyboard, bool required = false}) =>
      AppFormField(
        controller: c,
        label: label,
        hint: hint,
        maxLines: maxLines,
        keyboardType: keyboard,
        required: required,
      );

  Widget _number(TextEditingController c, String label, {String? hint}) =>
      AppFormField(
        controller: c,
        label: label,
        hint: hint,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      );

  /// Two (or three) fields side by side; stacked on narrow phones only when
  /// there are three.
  Widget _row(List<Widget> children, {bool keepTogether = false}) {
    final narrow =
        FomraLayout.isMobile(context) && children.length > 2 && !keepTogether;
    if (narrow) {
      return Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(child: children[i]),
      ],
    ]);
  }

  Widget _chips<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == selected,
            onSelected: (_) => setState(() => onSelected(v)),
          ),
      ]);

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.fomraTextSecondary)),
      );

  Widget _dateButton(String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
    return OutlinedButton.icon(
      onPressed: () async {
        final d = await _pickDate(value);
        if (d != null) setState(() => onChanged(d));
      },
      onLongPress: value == null ? null : () => setState(() => onChanged(null)),
      icon: const Icon(Icons.event_outlined, size: 18),
      label: Text(value == null
          ? label
          : '$label: ${DateFormat('d MMM yyyy').format(value)}'),
    );
  }

  Widget _locationCard() {
    final pin = _pin;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(pin == null ? Icons.location_off_outlined : Icons.location_on,
              color: pin == null ? context.fomraTextSecondary : AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pin == null
                  ? 'No pin yet: needed to show it near our sites.'
                  : '${pin.latitude.toStringAsFixed(6)}, '
                      '${pin.longitude.toStringAsFixed(6)}'
                      '${_gpsNote.isEmpty ? '' : ' · $_gpsNote'}',
              style: TextStyle(fontSize: 13.5, color: context.fomraTextPrimary),
            ),
          ),
          if (pin != null) ...[
            IconButton(
              tooltip: 'Open in Google Maps',
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              onPressed: () => MapsNavigation.navigateTo(
                  lat: pin.latitude, lng: pin.longitude),
            ),
            IconButton(
              tooltip: 'Remove pin',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(() => _pin = null),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: _locating ? null : _useMyLocation,
            icon: _locating
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded, size: 18),
            label: const Text("I'm at the project: use my location"),
          ),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AppFormField(
              controller: _mapsLink,
              label: 'Google Maps link or coordinates',
              hint: 'https://maps.app.goo.gl/… or 12.91, 80.03',
              keyboardType: TextInputType.url,
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton(
              onPressed: _readingLink ? null : _readLink,
              child: _readingLink
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Set pin'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _contactEditor(int i) {
    final c = _contacts[i];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _row([
              _text(c.name, 'Name'),
              _text(c.phone, 'Phone', keyboard: TextInputType.phone),
            ]),
          ),
          IconButton(
            tooltip: c.isMain ? 'Main contact' : 'Make main contact',
            icon: Icon(c.isMain ? Icons.star_rounded : Icons.star_outline_rounded,
                color: c.isMain ? AppColors.warning : context.fomraTextSecondary),
            onPressed: () => setState(() {
              for (final x in _contacts) {
                x.isMain = identical(x, c);
              }
            }),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<CompetitorContactRole>(
              initialValue: c.role,
              decoration: const InputDecoration(labelText: 'Role', isDense: true),
              items: [
                for (final r in CompetitorContactRole.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => setState(() => c.role = r ?? c.role),
            ),
          ),
          if (_contacts.length > 1)
            IconButton(
              tooltip: 'Remove contact',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => setState(() {
                final wasMain = c.isMain;
                _contacts.removeAt(i).dispose();
                if (wasMain && _contacts.isNotEmpty) _contacts.first.isMain = true;
              }),
            ),
        ]),
      ]),
    );
  }

  Widget _phaseEditor(int i) {
    final d = _phases[i];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _text(d.label, 'Phase')),
          if (_phases.length > 1)
            IconButton(
              tooltip: 'Remove phase',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => setState(() => _phases.removeAt(i).dispose()),
            ),
        ]),
        const SizedBox(height: 12),
        _row([
          _number(d.plots, 'Plots'),
          _number(d.sold, 'Sold'),
          _number(d.left, 'Left'),
        ], keepTogether: true),
        if (_more) ...[
          const SizedBox(height: 12),
          _row([
            _number(d.minSqft, 'Smallest plot (sq ft)'),
            _number(d.maxSqft, 'Largest plot (sq ft)'),
          ]),
          const SizedBox(height: 8),
          _dateButton('Launched', d.launch, (v) => d.launch = v),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    const section = SizedBox(height: 24);
    return Scaffold(
      backgroundColor: context.fomraPageBg,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit ${_e!.code}' : 'Add competitor project'),
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: FomraLayout.pagePadding(context).copyWith(bottom: 120),
            children: [
              if (!_isEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'Fill what you know now; the rest can be added later from '
                    "the project's page.",
                    style: TextStyle(fontSize: 13.5, color: context.fomraTextSecondary),
                  ),
                ),
              AppFormSection(
                title: 'Project',
                icon: Icons.apartment_rounded,
                children: [
                  _text(_name, 'Project name', required: true),
                  _text(_builder, 'Builder / developer'),
                  _label('Type'),
                  _chips<CompetitorType>(
                    values: CompetitorType.values,
                    selected: _type,
                    label: (t) => t.label,
                    onSelected: (t) => _type = t,
                  ),
                  _label('Stage'),
                  _chips<CompetitorStage>(
                    values: CompetitorStage.values,
                    selected: _stage,
                    label: (s) => s.label,
                    onSelected: (s) => _stage = s,
                  ),
                ],
              ),
              section,
              AppFormSection(
                title: 'Location',
                icon: Icons.place_outlined,
                children: [
                  _locationCard(),
                  _row([
                    _text(_village, 'Village'),
                    if (_more) _text(_taluk, 'Taluk'),
                  ]),
                  if (_more) _text(_district, 'District'),
                ],
              ),
              section,
              AppFormSection(
                title: 'Price (₹ per sq ft)',
                icon: Icons.currency_rupee_rounded,
                children: [
                  _row([
                    _number(_quoted, 'Quoted price'),
                    _number(_negotiated, 'Negotiated price'),
                  ]),
                  if (_more) ...[
                    _row([
                      _number(_pre, 'Pre-launch price'),
                      _number(_glv, 'GLV (guideline value)'),
                    ]),
                    _label('PLC: extra ₹ per sq ft'),
                    _row([
                      _number(_plcCorner, 'Corner'),
                      _number(_plcFacing, 'East / North facing'),
                      _number(_plcRoad, 'Main road'),
                    ]),
                  ],
                ],
              ),
              section,
              AppFormSection(
                title: 'Size & plots',
                icon: Icons.grid_view_rounded,
                children: [
                  _row([
                    _number(_extent, 'Extent (acres)'),
                    if (_more) _number(_road, 'Main road width (ft)'),
                  ]),
                  _row([
                    _number(_minSqft, 'Smallest plot (sq ft)'),
                    _number(_maxSqft, 'Largest plot (sq ft)'),
                  ]),
                  for (var i = 0; i < _phases.length; i++) _phaseEditor(i),
                  if (_more)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _phases.add(
                            _PhaseDraft(defaultLabel: 'Phase ${_phases.length + 1}'))),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add phase'),
                      ),
                    ),
                ],
              ),
              if (!_isEdit) ...[
                section,
                AppFormSection(
                  title: 'Photo',
                  icon: Icons.photo_camera_outlined,
                  children: [
                    Row(children: [
                      if (_photo != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_photo!,
                              width: 84, height: 84, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 12),
                      ],
                      OutlinedButton.icon(
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: Text(_photo == null ? 'Add a photo' : 'Change photo'),
                      ),
                      if (_photo != null)
                        IconButton(
                          tooltip: 'Remove photo',
                          onPressed: () => setState(() => _photo = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ]),
                  ],
                ),
              ],
              section,
              if (!_more)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _more = true),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: const Text(
                      'More details: approvals, PLC, charges, sales contacts, phases'),
                )
              else ...[
                AppFormSection(
                  title: 'Approvals',
                  icon: Icons.verified_outlined,
                  children: [
                    _row([
                      _text(_authority, 'Approved by', hint: 'DTCP / CMDA'),
                      _text(_approvalNo, 'Approval no.'),
                    ]),
                    _text(_rera, 'RERA no.'),
                    _dateButton('Launch date', _launch, (v) => _launch = v),
                  ],
                ),
                section,
                AppFormSection(
                  title: 'Charges',
                  icon: Icons.receipt_long_outlined,
                  children: [
                    _row([
                      _number(_docs, 'Documentation (₹)'),
                      _number(_maintenance, 'Maintenance (₹)'),
                      _number(_corpus, 'Corpus (₹)'),
                    ]),
                    _text(_otherCharges, 'Other charges'),
                  ],
                ),
                section,
                AppFormSection(
                  title: 'Sales contacts',
                  subtitle: 'Everyone we speak to there. Star the main contact.',
                  icon: Icons.support_agent_outlined,
                  children: [
                    for (var i = 0; i < _contacts.length; i++) _contactEditor(i),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _contacts.add(
                            _ContactDraft(isMain: _contacts.isEmpty))),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Add another contact'),
                      ),
                    ),
                  ],
                ),
                section,
                AppFormSection(
                  title: 'Amenities & notes',
                  icon: Icons.park_outlined,
                  children: [
                    _text(_amenities, 'Amenities', maxLines: 3),
                    _text(_notes, 'Notes', maxLines: 4),
                  ],
                ),
              ],
              gap,
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FormActionBar(
            submitLabel: _isEdit ? 'Save' : 'Add project',
            submitIcon: Icons.check_rounded,
            loading: _saving,
            onSubmit: _saving ? null : _save,
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}
