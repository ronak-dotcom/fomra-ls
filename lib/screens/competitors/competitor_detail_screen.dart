import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/competitor_project.dart';
import '../../models/employee_profile.dart';
import '../../models/land_lead.dart';
import '../../services/app_store.dart';
import '../../services/auth_service.dart';
import '../../services/competitor_service.dart';
import '../../services/role_access.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/competitor_analysis.dart';
import '../../utils/image_compressor.dart';
import '../../utils/lead_location_parser.dart';
import '../../utils/maps_navigation.dart';
import '../../widgets/contact_call_whatsapp.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';
import '../land_lead/lead_detail_screen.dart';
import 'competitor_dialogs.dart';
import 'competitor_form_screen.dart';
import 'competitor_map.dart';
import 'competitor_widgets.dart';

/// One competitor project: prices, phases, sales pace, checks over time,
/// photos & documents, sales contact and the leads it sits next to.
class CompetitorDetailScreen extends StatefulWidget {
  final String projectId;
  const CompetitorDetailScreen({super.key, required this.projectId});

  @override
  State<CompetitorDetailScreen> createState() => _CompetitorDetailScreenState();
}

class _CompetitorDetailScreenState extends State<CompetitorDetailScreen> {
  List<CompetitorCheck>? _checks;
  List<CompetitorMedia>? _media;
  final Map<String, String> _urls = {};
  bool _uploading = false;

  CompetitorProject? get _p => CompetitorService.instance.byId(widget.projectId);

  @override
  void initState() {
    super.initState();
    CompetitorService.instance.addListener(_rebuild);
    CompetitorService.instance.ensureLoaded();
    _loadHistory();
  }

  @override
  void dispose() {
    CompetitorService.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    final svc = CompetitorService.instance;
    try {
      final checks = await svc.checks(widget.projectId);
      final media = await svc.media(widget.projectId);
      for (final m in media.where((m) => m.isPhoto)) {
        _urls[m.storagePath] ??= await svc.signedUrl(m.storagePath);
      }
      if (!mounted) return;
      setState(() {
        _checks = checks;
        _media = media;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _checks ??= const [];
          _media ??= const [];
        });
      }
    }
  }

  Future<void> _check(CompetitorProject p) async {
    final saved = await showCompetitorCheckDialog(context, p);
    if (saved != null) _loadHistory();
  }

  Future<void> _edit(CompetitorProject p) async {
    await CompetitorFormScreen.open(context, existing: p);
  }

  Future<void> _linkLead(CompetitorProject p) async {
    final leads = await pickLeads(context,
        title: 'Link ${p.name} to leads',
        leads: AppStore.instance.visibleLeads,
        exclude: p.linkedLeadIds.toSet());
    if (leads.isEmpty) return;
    try {
      await CompetitorService.instance
          .linkLeads(p.id, [for (final l in leads) l.leadId]);
      if (mounted) {
        AppFeedback.success(context,
            'Linked to ${leads.map((l) => '#${l.leadId}').join(', ')}.');
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not link: $e');
    }
  }

  Future<void> _unlink(CompetitorProject p, String leadId) async {
    try {
      await CompetitorService.instance.unlink(p.id, leadId);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not remove: $e');
    }
  }

  Future<void> _reassign(CompetitorProject p) async {
    final people = [
      for (final e in AppStore.instance.employees)
        if (e.status == EmployeeStatus.active && e.email.trim().isNotEmpty) e,
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    final picked = await showFomraDialog<EmployeeProfile>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Who owns this project?'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'The owner keeps it up to date and gets its re-check reminders.',
              style: TextStyle(fontSize: 13, color: ctx.fomraTextSecondary),
            ),
          ),
          for (final e in people)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e),
              child: Text(
                '${e.fullName}${e.designation.isEmpty ? '' : ' · ${e.designation}'}',
                style: TextStyle(
                  fontWeight: e.email.toLowerCase() == p.ownerEmail.toLowerCase()
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    try {
      await CompetitorService.instance.reassign(p.id, picked.fullName, picked.email);
      if (mounted) AppFeedback.success(context, '${picked.fullName} now owns ${p.code}.');
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not change: $e');
    }
  }

  Future<void> _delete(CompetitorProject p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${p.code} ${p.name}?'),
        content: const Text(
            'Its checks, photos, documents and lead links are deleted too. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await CompetitorService.instance.delete(p.id);
      if (!mounted) return;
      AppFeedback.success(context, 'Deleted ${p.code}.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppFeedback.error(context, '$e');
    }
  }

  Future<void> _addPhoto(CompetitorProject p, ImageSource source) async {
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, maxWidth: 2400, imageQuality: 90);
      if (picked == null) return;
      setState(() => _uploading = true);
      final bytes = await ImageCompressor.compressTo250Kb(await picked.readAsBytes());
      await CompetitorService.instance.uploadMedia(p.id, bytes,
          fileName: picked.name, kind: 'photo', contentType: 'image/jpeg');
      await _loadHistory();
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not add the photo: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addDocument(CompetitorProject p) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx', 'xls', 'xlsx'],
      withData: true,
    );
    final f = result?.files.firstOrNull;
    if (f?.bytes == null) return;
    if (f!.bytes!.length > 10 * 1024 * 1024) {
      if (mounted) AppFeedback.warning(context, '${f.name} is over 10 MB.');
      return;
    }
    final ext = (f.extension ?? '').toLowerCase();
    final type = switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/octet-stream',
    };
    setState(() => _uploading = true);
    try {
      await CompetitorService.instance.uploadMedia(p.id, f.bytes!,
          fileName: f.name, kind: 'document', contentType: type);
      await _loadHistory();
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not add the document: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openMedia(CompetitorMedia m) async {
    try {
      final url = _urls[m.storagePath] ??
          await CompetitorService.instance.signedUrl(m.storagePath);
      if (!mounted) return;
      if (m.isPhoto) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: Stack(children: [
              InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ]),
          ),
        );
      } else {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not open: $e');
    }
  }

  Future<void> _removeMedia(CompetitorMedia m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.isPhoto ? 'this photo' : m.fileName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CompetitorService.instance.deleteMedia(m);
      await _loadHistory();
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not remove: $e');
    }
  }

  void _openLead(LandLead l) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LeadDetailScreen(lead: l),
      ));

  // ── Layout ─────────────────────────────────────────────────────────────

  Widget _card(String title, IconData icon, List<Widget> children, {Widget? trailing}) =>
      AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: context.fomraTextPrimary)),
            ),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  Widget _kv(String k, String? v) {
    if (v == null || v.trim().isEmpty || v == '—') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 150,
          child: Text(k,
              style: TextStyle(fontSize: 13, color: context.fomraTextSecondary)),
        ),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: context.fomraTextPrimary)),
        ),
      ]),
    );
  }

  Widget _bigNumber(String label, String value, {Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color ?? context.fomraTextPrimary)),
          Text(label,
              style: TextStyle(fontSize: 12, color: context.fomraTextSecondary)),
        ],
      );

  String _date(DateTime? d) => d == null ? '' : DateFormat('d MMM yyyy').format(d);

  Widget _priceCard(CompetitorProject p) {
    final plc = [
      if (p.plcCorner != null) 'Corner +${rupees(p.plcCorner)}',
      if (p.plcFacing != null) 'Facing +${rupees(p.plcFacing)}',
      if (p.plcRoad != null) 'Main road +${rupees(p.plcRoad)}',
    ].join(' · ');
    return _card('Price per sq ft', Icons.currency_rupee_rounded, [
      Wrap(spacing: 28, runSpacing: 12, children: [
        _bigNumber('Negotiated', rupees(p.negotiatedPrice), color: AppColors.success),
        _bigNumber('Quoted', rupees(p.quotedPrice)),
        if (p.preLaunchPrice != null) _bigNumber('Pre-launch', rupees(p.preLaunchPrice)),
        if (p.glv != null) _bigNumber('GLV', rupees(p.glv)),
      ]),
      const SizedBox(height: 14),
      _kv('PLC (extra)', plc),
      _kv('Documentation', p.documentationCharges == null ? null : rupees(p.documentationCharges)),
      _kv('Maintenance', p.maintenanceCharge == null ? null : rupees(p.maintenanceCharge)),
      _kv('Corpus', p.corpus == null ? null : rupees(p.corpus)),
      _kv('Other charges', p.otherCharges),
    ]);
  }

  Widget _plotsCard(CompetitorProject p) {
    final pace = plotsPerMonth(p);
    final plots = p.totalPlots, sold = p.totalSold, left = p.totalAvailable;
    final soldShare = plots != null && plots > 0 && sold != null ? sold / plots : null;
    return _card('Plots & sales', Icons.grid_view_rounded, [
      Wrap(spacing: 28, runSpacing: 12, children: [
        _bigNumber('Plots', count(plots)),
        _bigNumber('Sold', count(sold)),
        _bigNumber('Left', count(left)),
        if (pace != null)
          _bigNumber('Sold per month', pace.toStringAsFixed(1), color: AppColors.primary),
      ]),
      if (soldShare != null) ...[
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: soldShare.clamp(0, 1).toDouble(),
            minHeight: 8,
            backgroundColor: context.fomraBorder,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 4),
        Text('${(soldShare * 100).round()}% sold',
            style: TextStyle(fontSize: 12, color: context.fomraTextSecondary)),
      ],
      if (p.phases.isNotEmpty) ...[
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 44,
            columnSpacing: 22,
            columns: const [
              DataColumn(label: Text('Phase')),
              DataColumn(label: Text('Launched')),
              DataColumn(label: Text('Plots'), numeric: true),
              DataColumn(label: Text('Sold'), numeric: true),
              DataColumn(label: Text('Left'), numeric: true),
              DataColumn(label: Text('Sizes (sq ft)')),
            ],
            rows: [
              for (final ph in p.phases)
                DataRow(cells: [
                  DataCell(Text(ph.label)),
                  DataCell(Text(ph.launchDate == null
                      ? ''
                      : DateFormat('MMM yyyy').format(ph.launchDate!))),
                  DataCell(Text(count(ph.plots))),
                  DataCell(Text(count(ph.sold))),
                  DataCell(Text(count(ph.available))),
                  DataCell(Text(ph.minPlotSqft == null && ph.maxPlotSqft == null
                      ? ''
                      : '${count(ph.minPlotSqft)}–${count(ph.maxPlotSqft)}')),
                ]),
            ],
          ),
        ),
      ],
      const SizedBox(height: 8),
      _kv('Plot sizes',
          p.minSqft == null && p.maxSqft == null
              ? null
              : '${count(p.minSqft)}–${count(p.maxSqft)} sq ft'),
      _kv('Extent', p.extentAcres == null ? null : '${acresLabel(p.extentAcres!)} acres'),
      _kv('Launched', _date(p.firstLaunch)),
    ]);
  }

  Widget _detailsCard(CompetitorProject p) => _card('Approvals & place', Icons.verified_outlined, [
        _kv('Approved by', [p.approvalAuthority, p.approvalNo].where((s) => s.isNotEmpty).join(' ')),
        _kv('RERA', p.reraNo),
        _kv('Main road', p.mainRoadFt == null ? null : '${count(p.mainRoadFt)} ft'),
        _kv('Village', p.village),
        _kv('Taluk', p.taluk),
        _kv('District', p.district),
        _kv('Pin',
            p.point == null
                ? 'No pin yet (edit to add)'
                : '${p.lat!.toStringAsFixed(5)}, ${p.lng!.toStringAsFixed(5)}'
                    '${p.gpsNote.isEmpty ? '' : ' · ${p.gpsNote}'}'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (p.point != null)
            OutlinedButton.icon(
              onPressed: () => MapsNavigation.navigateTo(lat: p.lat!, lng: p.lng!),
              icon: const Icon(Icons.directions_outlined, size: 18),
              label: const Text('Open in Google Maps'),
            ),
          if (p.mapsLink.startsWith('http'))
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(p.mapsLink),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('Saved map link'),
            ),
        ]),
      ]);

  Future<void> _saveContacts(CompetitorProject p, List<CompetitorContact> list,
      String done) async {
    try {
      await CompetitorService.instance.saveContacts(p, list);
      if (mounted) AppFeedback.success(context, done);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not save: $e');
    }
  }

  Future<void> _addContact(CompetitorProject p) async {
    final c = await showContactDialog(context);
    if (c == null) return;
    final list = [
      for (final x in p.allContacts) c.isMain ? x.copyWith(isMain: false) : x,
      c,
    ];
    await _saveContacts(p, list, 'Added ${c.name.isEmpty ? c.phone : c.name}.');
  }

  Future<void> _contactAction(CompetitorProject p, int i, String action) async {
    final list = [...p.allContacts];
    if (i < 0 || i >= list.length) return;
    final c = list[i];
    switch (action) {
      case 'edit':
        final edited = await showContactDialog(context, existing: c);
        if (edited == null) return;
        list[i] = edited;
        if (edited.isMain) {
          for (var j = 0; j < list.length; j++) {
            if (j != i) list[j] = list[j].copyWith(isMain: false);
          }
        }
        await _saveContacts(p, list, 'Saved.');
      case 'main':
        await _saveContacts(
            p,
            [for (var j = 0; j < list.length; j++) list[j].copyWith(isMain: j == i)],
            '${c.name} is now the main contact.');
      case 'remove':
        list.removeAt(i);
        await _saveContacts(p, list, 'Removed ${c.name}.');
    }
  }

  Widget _salesCard(CompetitorProject p) {
    final contacts = p.allContacts;
    return _card(
      'Sales contacts',
      Icons.support_agent_outlined,
      [
        if (contacts.isEmpty)
          Text('No sales contact yet.',
              style: TextStyle(fontSize: 13, color: context.fomraTextSecondary)),
        for (final (i, c) in contacts.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(c.isMain ? Icons.star_rounded : Icons.person_outline_rounded,
                  size: 18,
                  color: c.isMain ? AppColors.warning : context.fomraTextSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name.isEmpty ? 'No name' : c.name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.fomraTextPrimary)),
                    Text(
                      [c.role.label, if (c.phone.isNotEmpty) c.phone,
                        if (c.isMain) 'main contact'].join(' · '),
                      style: TextStyle(
                          fontSize: 12.5, color: context.fomraTextSecondary),
                    ),
                  ],
                ),
              ),
              ContactCallWhatsApp(
                  contact: c.phone, accent: AppColors.primary, size: 32, iconSize: 16),
              PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (a) => _contactAction(p, i, a),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (!c.isMain)
                      const PopupMenuItem(
                          value: 'main', child: Text('Make main contact')),
                    const PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
            ]),
          ),
        if (p.amenities.isNotEmpty || p.notes.isNotEmpty) const Divider(height: 18),
        if (p.amenities.isNotEmpty)
          Text(p.amenities,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: context.fomraTextPrimary)),
        if (p.notes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(p.notes,
              style: TextStyle(fontSize: 13, height: 1.4, color: context.fomraTextSecondary)),
        ],
      ],
      trailing: TextButton.icon(
        onPressed: () => _addContact(p),
        icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
        label: const Text('Add'),
      ),
    );
  }

  Widget _leadsCard(CompetitorProject p) {
    final leads = AppStore.instance.visibleLeads;
    final byId = {for (final l in leads) l.leadId: l};
    final near = <(LandLead, double)>[];
    if (p.point != null) {
      for (final l in leads) {
        final pin = parseLeadGps(l.gpsCoordinates);
        if (pin == null) continue;
        final km = kmBetween(p.point!, pin);
        if (km <= 10) near.add((l, km));
      }
      near.sort((a, b) => a.$2.compareTo(b.$2));
    }
    return _card(
      'Our leads',
      Icons.location_on_outlined,
      [
        if (p.linkedLeadIds.isEmpty && near.isEmpty)
          Text('No lead within 10 km and none linked.',
              style: TextStyle(fontSize: 13, color: context.fomraTextSecondary)),
        for (final id in p.linkedLeadIds)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link_rounded, size: 18),
            title: Text(byId[id] == null ? 'Lead #$id' : '#$id · ${byId[id]!.displayName}'),
            subtitle: const Text('Linked by hand'),
            onTap: byId[id] == null ? null : () => _openLead(byId[id]!),
            trailing: IconButton(
              tooltip: 'Remove link',
              icon: const Icon(Icons.link_off_rounded, size: 18),
              onPressed: () => _unlink(p, id),
            ),
          ),
        for (final (l, km) in near.where((n) => !p.linkedLeadIds.contains(n.$1.leadId)).take(8))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.near_me_outlined, size: 18),
            title: Text('#${l.leadId} · ${l.displayName}'),
            subtitle: Text('${km.toStringAsFixed(1)} km away'),
            onTap: () => _openLead(l),
          ),
      ],
      trailing: TextButton.icon(
        onPressed: () => _linkLead(p),
        icon: const Icon(Icons.add_link_rounded, size: 18),
        label: const Text('Link'),
      ),
    );
  }

  Widget _checksCard(CompetitorProject p) {
    final checks = _checks;
    return _card(
      'Price & sales checks',
      Icons.timeline_rounded,
      [
        if (checks == null)
          const Center(child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ))
        else if (checks.isEmpty)
          Text('No checks yet.',
              style: TextStyle(fontSize: 13, color: context.fomraTextSecondary))
        else
          for (var i = 0; i < checks.length; i++)
            _checkRow(checks[i], i + 1 < checks.length ? checks[i + 1] : null),
      ],
      trailing: TextButton.icon(
        onPressed: () => _check(p),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('New check'),
      ),
    );
  }

  Widget _checkRow(CompetitorCheck c, CompetitorCheck? before) {
    final now = c.negotiatedPrice ?? c.quotedPrice;
    final was = before?.negotiatedPrice ?? before?.quotedPrice;
    final diff = now != null && was != null ? now - was : null;
    final parts = [
      if (c.quotedPrice != null) 'Quoted ${rupees(c.quotedPrice)}',
      if (c.negotiatedPrice != null) 'Negotiated ${rupees(c.negotiatedPrice)}',
      if (c.sold != null) '${c.sold} sold',
      if (c.available != null) '${c.available} left',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 10,
          height: 10,
          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${_date(c.checkedAt)}${c.checkedByName.isEmpty ? '' : ' · ${c.checkedByName}'}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextPrimary),
                ),
              ),
              if (diff != null && diff != 0)
                Text(
                  '${diff > 0 ? '▲' : '▼'} ${rupees(diff.abs())}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: diff > 0 ? AppColors.success : AppColors.error),
                ),
            ]),
            if (parts.isNotEmpty)
              Text(parts.join(' · '),
                  style: TextStyle(fontSize: 12.5, color: context.fomraTextSecondary)),
            if (c.notes.isNotEmpty)
              Text(c.notes,
                  style: TextStyle(fontSize: 12.5, color: context.fomraTextSecondary)),
          ]),
        ),
      ]),
    );
  }

  Widget _mediaCard(CompetitorProject p) {
    final media = _media;
    final photos = media?.where((m) => m.isPhoto).toList() ?? const [];
    final docs = media?.where((m) => !m.isPhoto).toList() ?? const [];
    return _card(
      'Photos & documents',
      Icons.photo_library_outlined,
      [
        if (media == null)
          const Center(child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ))
        else ...[
          if (photos.isEmpty && docs.isEmpty)
            Text('No photos or documents yet: brochure, price list, layout plan…',
                style: TextStyle(fontSize: 13, color: context.fomraTextSecondary)),
          if (photos.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in photos)
                GestureDetector(
                  onTap: () => _openMedia(m),
                  onLongPress: () => _removeMedia(m),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _urls[m.storagePath] == null
                        ? Container(width: 96, height: 96, color: context.fomraBorder)
                        : Image.network(_urls[m.storagePath]!,
                            width: 96, height: 96, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                width: 96, height: 96, color: context.fomraBorder,
                                child: const Icon(Icons.broken_image_outlined))),
                  ),
                ),
            ]),
          for (final m in docs)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(m.fileName.isEmpty ? 'Document' : m.fileName),
              subtitle: Text(
                  '${_date(m.createdAt)}${m.uploadedByName.isEmpty ? '' : ' · ${m.uploadedByName}'}'),
              onTap: () => _openMedia(m),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                onPressed: () => _removeMedia(m),
              ),
            ),
          if (photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Tap a photo to view · long-press to remove.',
                  style: TextStyle(fontSize: 11.5, color: context.fomraTextSecondary)),
            ),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _uploading ? null : () => _addPhoto(p, ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('Take photo'),
          ),
          OutlinedButton.icon(
            onPressed: _uploading ? null : () => _addPhoto(p, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('From gallery'),
          ),
          OutlinedButton.icon(
            onPressed: _uploading ? null : () => _addDocument(p),
            icon: const Icon(Icons.attach_file_rounded, size: 18),
            label: const Text('Document'),
          ),
          if (_uploading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ]),
      ],
    );
  }

  Widget _ownerLine(CompetitorProject p) {
    final isMgmt = AuthService.instance.isManagement;
    return Row(children: [
      Icon(Icons.person_outline_rounded, size: 16, color: context.fomraTextSecondary),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          'Owner: ${p.ownerName.isEmpty ? 'not set' : p.ownerName}'
          '${p.source == 'import' ? " · from the team's sheet" : p.createdByName.isEmpty ? '' : ' · added by ${p.createdByName}'
              '${p.createdAt.year > 1970 ? ' on ${_date(p.createdAt)}' : ''}'}',
          style: TextStyle(fontSize: 12.5, color: context.fomraTextSecondary),
        ),
      ),
      if (isMgmt)
        TextButton(onPressed: () => _reassign(p), child: const Text('Change owner')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return Scaffold(
        backgroundColor: context.fomraPageBg,
        appBar: AppBar(
            backgroundColor: AppColors.ink, foregroundColor: Colors.white),
        body: Center(
          child: CompetitorService.instance.isLoaded
              ? const Text('This project is no longer in the list.')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final wide = FomraLayout.isDesktop(context);
    final nearbyLeads = [
      for (final l in AppStore.instance.visibleLeads)
        if (p.point != null &&
            parseLeadGps(l.gpsCoordinates) != null &&
            kmBetween(p.point!, parseLeadGps(l.gpsCoordinates)!) <= 10)
          l,
    ];

    final header = AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.code,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextSecondary)),
              Text(p.name,
                  style: TextStyle(
                      fontSize: FomraLayout.responsiveClamp(context, min: 20, max: 24),
                      fontWeight: FontWeight.w800,
                      color: context.fomraTextPrimary)),
              const SizedBox(height: 2),
              Text(
                [
                  if (p.builder.isNotEmpty) p.builder,
                  p.type.label,
                  if (p.placeLabel.isNotEmpty) p.placeLabel,
                ].join(' · '),
                style: TextStyle(fontSize: 13.5, color: context.fomraTextSecondary),
              ),
            ]),
          ),
          CompetitorStageChip(stage: p.stage),
        ]),
        const SizedBox(height: 10),
        CompetitorFreshness(project: p),
        const SizedBox(height: 6),
        _ownerLine(p),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () => _check(p),
            icon: const Icon(Icons.price_check_rounded, size: 18),
            label: const Text('Price check'),
          ),
          OutlinedButton.icon(
            onPressed: () => _edit(p),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          OutlinedButton.icon(
            onPressed: () => _linkLead(p),
            icon: const Icon(Icons.add_link_rounded, size: 18),
            label: const Text('Link to a lead'),
          ),
        ]),
      ]),
    );

    final map = p.point == null
        ? null
        : SizedBox(
            height: 280,
            child: CompetitorMap(
              projects: [p],
              leads: nearbyLeads,
              onOpenProject: (_) {},
              onOpenLead: _openLead,
            ),
          );

    final left = [
      _priceCard(p),
      _plotsCard(p),
      _checksCard(p),
    ];
    final right = [
      if (map != null) map,
      _leadsCard(p),
      _salesCard(p),
      _detailsCard(p),
      _mediaCard(p),
    ];

    List<Widget> spaced(List<Widget> ws) => [
          for (var i = 0; i < ws.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            ws[i],
          ],
        ];

    return Scaffold(
      backgroundColor: context.fomraPageBg,
      appBar: AppBar(
        title: Text('${p.code} · ${p.name}'),
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        actions: [
          if (RoleAccess.canDelete)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _delete(p);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete project')),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await CompetitorService.instance.ensureLoaded(force: true);
          await _loadHistory();
        },
        child: ListView(
          padding: FomraLayout.pagePadding(context),
          children: [
            header,
            const SizedBox(height: 14),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: spaced(left))),
                const SizedBox(width: 14),
                Expanded(child: Column(children: spaced(right))),
              ])
            else
              ...spaced([
                if (map != null) map,
                _priceCard(p),
                _plotsCard(p),
                _leadsCard(p),
                _checksCard(p),
                _salesCard(p),
                _detailsCard(p),
                _mediaCard(p),
              ]),
          ],
        ),
      ),
    );
  }
}
