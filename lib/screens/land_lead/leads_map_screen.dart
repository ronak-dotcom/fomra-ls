import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../config/maptiler_tiles.dart';
import '../../models/land_lead.dart';
import '../../services/lead_visibility.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/lead_location_parser.dart';
import '../../utils/maps_navigation.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/lead_portfolio_breakdown.dart';
import '../../widgets/map_layer_toggle.dart';
import '../../widgets/fomra_breadcrumb.dart';
import '../../widgets/portal_page_layout.dart';
import '../../widgets/ui/multi_select_field.dart';
import 'filtered_leads_screen.dart';
import 'lead_detail_screen.dart';

class _PlottedLead {
  final LandLead lead;
  final LatLng point;

  const _PlottedLead({required this.lead, required this.point});
}

class LeadsMapScreen extends StatefulWidget {
  final List<LandLead> leads;

  const LeadsMapScreen({super.key, required this.leads});

  @override
  State<LeadsMapScreen> createState() => _LeadsMapScreenState();
}

class _LeadsMapScreenState extends State<LeadsMapScreen> {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _satelliteLayer = false;

  /// The pin whose compact details card is shown on the map (null = none).
  _PlottedLead? _selectedPin;

  // Shared metrics so the search box, dropdowns and date field line up as one
  // consistent set of controls.
  static const double _kFieldHeight = 44;
  static const double _kFieldRadius = 10;
  static const double _kControlGap = 12;

  // ── Filters ────────────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  final Set<LeadStatus> _stages = {};
  Set<String> _executive = {};
  Set<String> _broker = {};
  DateTimeRange? _dateFilter;

  /// Filters excluding the free-text search — drives the "Filters" badge.
  bool get _hasFieldFilters =>
      _stages.isNotEmpty ||
      _executive.isNotEmpty ||
      _broker.isNotEmpty ||
      _dateFilter != null;

  bool get _hasActiveFilters => _hasFieldFilters || _search.trim().isNotEmpty;

  void _clearFilters() {
    _search = '';
    _searchCtrl.clear();
    _stages.clear();
    _executive = {};
    _broker = {};
    _dateFilter = null;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Role-scoped source leads: an executive only ever sees the sites assigned
  /// to / created by them, and a Reporting Manager / Head sees their team or
  /// just themselves per the header toggle — even if the caller passed a
  /// broader list. Management sees everything. This enforces the access rule at
  /// the map itself.
  List<LandLead> get _scopedLeads => LeadVisibility.scope(widget.leads);

  List<String> _distinct(String Function(LandLead) selector) {
    final set = <String>{};
    for (final l in _scopedLeads) {
      final v = selector(l).trim();
      if (v.isNotEmpty) set.add(v);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<LandLead> get _filteredLeads {
    final q = _search.trim().toLowerCase();
    return _scopedLeads.where((l) {
      if (_stages.isNotEmpty && !_stages.contains(l.status)) return false;
      if (_executive.isNotEmpty &&
          !_executive.contains(l.createdByName.trim())) {
        return false;
      }
      if (_broker.isNotEmpty && !_broker.contains(l.brokerName.trim())) {
        return false;
      }
      if (_dateFilter != null) {
        final d = DateTime(l.addedOn.year, l.addedOn.month, l.addedOn.day);
        final start = DateTime(
            _dateFilter!.start.year, _dateFilter!.start.month, _dateFilter!.start.day);
        final end = DateTime(
            _dateFilter!.end.year, _dateFilter!.end.month, _dateFilter!.end.day);
        if (d.isBefore(start) || d.isAfter(end)) return false;
      }
      if (q.isNotEmpty) {
        final match = <String>[
          l.leadId,
          l.ownerName,
          l.surveyNumber,
          l.village,
          l.brokerName,
          l.createdByName,
        ].any((f) => f.toLowerCase().contains(q));
        if (!match) return false;
      }
      return true;
    }).toList();
  }

  List<_PlottedLead> _plottedFrom(List<LandLead> leads) {
    final out = <_PlottedLead>[];
    for (final lead in leads) {
      final point = parseLeadGps(lead.gpsCoordinates);
      if (point != null) out.add(_PlottedLead(lead: lead, point: point));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredLeads;
    final plotted = _plottedFrom(filtered);
    final totalAcres =
        filtered.fold<double>(0, (s, l) => s + leadPortfolioAcres(l));
    final missingGpsLeads =
        filtered.where((l) => parseLeadGps(l.gpsCoordinates) == null).toList();

    // Initial view uses the full (unfiltered) set so the camera is stable.
    final allPlotted = _plottedFrom(_scopedLeads);
    final initialView =
        allPlotted.isEmpty ? null : _computeCenterAndZoom(allPlotted);

    return FomraAppShell(
      currentRoute: '/land-lead',
      appBar: FomraSubPageAppBar(
        title: 'Project Map',
        // Compact KPI chips sit inline with the title in the header, so the
        // body — and therefore the map — keeps its full height.
        actions: allPlotted.isEmpty
            ? null
            : [
                _headerKpi(
                    '${filtered.length}', 'Sites', Icons.place_outlined),
                const SizedBox(width: 8),
                _headerKpi(totalAcres.toStringAsFixed(2), 'Acres',
                    Icons.landscape_outlined),
                const SizedBox(width: 12),
              ],
      ),
      body: allPlotted.isEmpty
          ? _buildEmpty(context)
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final map = _buildMap(context, plotted, initialView, missingGpsLeads);
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 320,
                        child: _sidePanel(context),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: map),
                    ],
                  );
                }
                return Column(
                  children: [
                    _compactSearchBar(context),
                    Expanded(child: map),
                  ],
                );
              },
            ),
    );
  }

  // ── Header KPI chip (rendered on the gradient app bar) ─────────────────────
  Widget _headerKpi(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Map ──────────────────────────────────────────────────────────────────
  Widget _buildMap(
    BuildContext context,
    List<_PlottedLead> plotted,
    (LatLng, double)? initialView,
    List<LandLead> missingGpsLeads,
  ) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialView!.$1,
            initialZoom: initialView.$2,
            onMapReady: () => setState(() => _mapReady = true),
          ),
          children: [
            MapTilerTiles.tileLayer(
              urlTemplate: MapTilerTiles.urlFor(satelliteLayer: _satelliteLayer),
              satelliteLayer: _satelliteLayer,
            ),
            MarkerLayer(
              markers: [
                ...plotted.map((p) {
                final color = p.lead.status.color;
                return Marker(
                  point: p.point,
                  width: 44,
                  height: 52,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPin = p),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Text(
                            p.lead.leadId.length > 8
                                ? p.lead.leadId
                                    .substring(p.lead.leadId.length - 6)
                                : p.lead.leadId,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(Icons.location_on, color: color, size: 36),
                      ],
                    ),
                  ),
                );
                }),
              ],
            ),
          ],
        ),
        if (missingGpsLeads.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              color: context.fomraSurface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => FilteredLeadsScreen.openList(
                  context,
                  title: 'Sites without GPS',
                  subtitle: 'Not shown on the map — add coordinates to plot these',
                  leads: missingGpsLeads,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${missingGpsLeads.length} matching site'
                          '${missingGpsLeads.length == 1 ? '' : 's'} '
                          'without GPS — not shown on the map.',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.fomraTextSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 16, color: context.fomraTextSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Layer toggle: top-left, offset below the GPS banner's typical
        // single-line height so the two don't overlap when both are shown.
        Positioned(
          left: 12,
          top: missingGpsLeads.isNotEmpty ? 64 : 12,
          child: MapLayerToggle(
            satellite: _satelliteLayer,
            onChanged: (v) => setState(() => _satelliteLayer = v),
          ),
        ),
        // Bottom overlay: the tapped pin's details card floats above the status
        // legend, which now stays visible instead of hiding. The popup is
        // rendered here in the map's outer Stack (not inside the MarkerLayer) so
        // its buttons receive taps reliably.
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_selectedPin != null) ...[
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: _PropertyPopup(
                      lead: _selectedPin!.lead,
                      onOpenSite: () => _openLead(context, _selectedPin!.lead),
                      onClose: () => setState(() => _selectedPin = null),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Material(
                color: context.fomraSurface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: leadStatusPipelineOrder
                        .map((s) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on, size: 14, color: s.color),
                                const SizedBox(width: 4),
                                Text(
                                  s.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: context.fomraTextSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!_mapReady) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  // ── Wide side panel: sticky search + scrollable filters ────────────────────
  Widget _sidePanel(BuildContext context) {
    return Material(
      color: context.fomraSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search stays pinned while the filter list scrolls beneath it.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: _searchField(context, (fn) => setState(fn)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _filterControls(context, (fn) => setState(fn)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Narrow: sticky search + Filters button (opens slide-over drawer) ───────
  Widget _compactSearchBar(BuildContext context) {
    return Material(
      color: context.fomraSurface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(child: _searchField(context, (fn) => setState(fn))),
            const SizedBox(width: 8),
            SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                onPressed: _openFilterDrawer,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: Badge(
                  isLabelVisible: _hasFieldFilters,
                  child: const Icon(Icons.tune_rounded, size: 18),
                ),
                label: const Text('Filters'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mobile filter panel as a right-side slide-over drawer.
  void _openFilterDrawer() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filters',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, _, __) {
        final width =
            math.min(360.0, MediaQuery.sizeOf(ctx).width * 0.86);
        return Align(
          alignment: Alignment.centerRight,
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              void apply(VoidCallback fn) {
                setState(fn);
                setSheet(() {});
              }

              return Material(
                color: context.fomraSurface,
                child: SizedBox(
                  width: width,
                  height: double.infinity,
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                          child: Row(
                            children: [
                              Text(
                                'Filters',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: context.fomraTextPrimary,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.close_rounded),
                                tooltip: 'Close',
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView(
                            padding:
                                const EdgeInsets.fromLTRB(20, 16, 20, 28),
                            children: [
                              _filterControls(context, apply),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    );
  }

  // ── Search field (leading icon; owner / survey / village / broker / ID) ────
  Widget _searchField(
    BuildContext context,
    void Function(VoidCallback) apply,
  ) {
    return SizedBox(
      height: _kFieldHeight,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => apply(() => _search = v),
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 13, color: context.fomraTextPrimary),
        decoration: InputDecoration(
          hintText: 'Search ID, owner, survey, village, broker, executive',
          hintStyle: TextStyle(
            fontSize: 12.5,
            color: context.fomraTextSecondary.withValues(alpha: 0.8),
          ),
          isDense: true,
          filled: true,
          fillColor: context.fomraSurfaceVar,
          prefixIcon: Icon(Icons.search_rounded,
              size: 18, color: context.fomraTextSecondary),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  splashRadius: 18,
                  onPressed: () => apply(() {
                    _search = '';
                    _searchCtrl.clear();
                  }),
                ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_kFieldRadius),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ── Filter controls (shared by side panel + slide-over drawer) ─────────────
  Widget _filterControls(
    BuildContext context,
    void Function(VoidCallback) apply,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(context, 'SITE STAGE'),
        const SizedBox(height: 8),
        MultiSelectField<LeadStatus>(
          label: 'Stage',
          icon: Icons.timeline_rounded,
          options: leadStatusPipelineOrder,
          selected: _stages,
          labelOf: (s) => s.label,
          onChanged: (v) => apply(() {
            _stages
              ..clear()
              ..addAll(v);
          }),
        ),
        const SizedBox(height: _kControlGap + 4),
        MultiSelectField<String>(
          label: 'Assigned Executive',
          icon: Icons.person_outline_rounded,
          options: _distinct((l) => l.createdByName),
          selected: _executive,
          labelOf: (s) => s,
          onChanged: (v) => apply(() => _executive = v),
        ),
        const SizedBox(height: _kControlGap),
        MultiSelectField<String>(
          label: 'Broker',
          icon: Icons.handshake_outlined,
          options: _distinct((l) => l.brokerName),
          selected: _broker,
          labelOf: (s) => s,
          onChanged: (v) => apply(() => _broker = v),
        ),
        const SizedBox(height: _kControlGap),
        _dateField(context, apply),
        const SizedBox(height: _kControlGap + 6),
        // Compact, full-width clear button at the bottom — replaces the small
        // top text link. Disabled (hidden) when nothing is active.
        if (_hasActiveFilters)
          SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: () => apply(_clearFilters),
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Clear All Filters',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.fomraTextSecondary,
                side: BorderSide(color: context.fomraBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_kFieldRadius),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
      ],
    );
  }

  /// Uniform section label above a group of filter controls.
  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: context.fomraTextSecondary,
      ),
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: context.fomraTextSecondary,
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: context.fomraTextSecondary,
      ),
      isDense: true,
      filled: true,
      fillColor: context.fomraSurfaceVar,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      // Tighter vertical padding trims each field ~25% while staying aligned
      // with the search box's height.
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_kFieldRadius),
        borderSide: BorderSide.none,
      ),
    );
  }

  // Compact outlined date field with a calendar icon — matches the dropdowns.
  Widget _dateField(
    BuildContext context,
    void Function(VoidCallback) apply,
  ) {
    final df = DateFormat('dd MMM yyyy');
    final hasDate = _dateFilter != null;
    return InkWell(
      borderRadius: BorderRadius.circular(_kFieldRadius),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 1),
          initialDateRange: _dateFilter,
          // A compact input dialog instead of the full-screen calendar (tap
          // the calendar icon inside to switch to the month view if needed)
          // — matches reports_screen.dart's date range picker.
          initialEntryMode: DatePickerEntryMode.input,
        );
        if (picked != null) apply(() => _dateFilter = picked);
      },
      child: InputDecorator(
        decoration: _fieldDecoration(
          context,
          label: 'Date added',
          prefixIcon: Icon(Icons.calendar_today_outlined,
              size: 16, color: context.fomraTextSecondary),
          suffixIcon: hasDate
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  splashRadius: 18,
                  onPressed: () => apply(() => _dateFilter = null),
                )
              : null,
        ),
        child: Text(
          hasDate
              ? (_dateFilter!.start == _dateFilter!.end
                  ? df.format(_dateFilter!.start)
                  : '${df.format(_dateFilter!.start)} – ${df.format(_dateFilter!.end)}')
              : 'Any date',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: hasDate
                ? context.fomraTextPrimary
                : context.fomraTextSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined,
                size: 56, color: AppColors.primary.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(
              'No sites with GPS coordinates',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.fomraTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add GPS when creating sites (tap the map in Add Site) '
              'so they appear here as pinned locations.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.fomraTextSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (LatLng, double) _computeCenterAndZoom(List<_PlottedLead> plotted) {
    if (plotted.length == 1) {
      return (plotted.first.point, 15);
    }

    var minLat = plotted.first.point.latitude;
    var maxLat = minLat;
    var minLng = plotted.first.point.longitude;
    var maxLng = minLng;

    for (final p in plotted) {
      minLat = minLat < p.point.latitude ? minLat : p.point.latitude;
      maxLat = maxLat > p.point.latitude ? maxLat : p.point.latitude;
      minLng = minLng < p.point.longitude ? minLng : p.point.longitude;
      maxLng = maxLng > p.point.longitude ? maxLng : p.point.longitude;
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final span = latSpan > lngSpan ? latSpan : lngSpan;

    double zoom;
    if (span > 2) {
      zoom = 7;
    } else if (span > 1) {
      zoom = 8;
    } else if (span > 0.5) {
      zoom = 9;
    } else if (span > 0.2) {
      zoom = 10;
    } else if (span > 0.08) {
      zoom = 11;
    } else if (span > 0.03) {
      zoom = 12;
    } else {
      zoom = 13;
    }

    return (center, zoom);
  }

  /// Navigate directly to the Land Lead Details page for the tapped site,
  /// matching the standard lead-detail navigation used across the app. The
  /// selected lead is passed by value so it loads immediately; role-based
  /// visibility is already enforced upstream (only scoped pins are shown).
  void _openLead(BuildContext context, LandLead lead) {
    Navigator.of(context).push(
      MaterialPageRoute(
        // Show where the lead was opened from: Home > Project Map > Lead #id.
        // Tapping "Project Map" pops back to this map.
        builder: (_) => LeadDetailScreen(
          lead: lead,
          breadcrumbs: [
            FomraBreadcrumbs.home,
            const FomraBreadcrumbItem.pop('Project Map'),
            FomraBreadcrumbItem.current('Lead #${lead.leadId}'),
          ],
        ),
      ),
    );
  }

}

String _siteName(LandLead l) {
  if (l.location.trim().isNotEmpty) return l.location.trim();
  final parts = <String>[
    if (l.surveyNumber.trim().isNotEmpty) 'Survey ${l.surveyNumber.trim()}',
    if (l.village.trim().isNotEmpty) l.village.trim(),
  ];
  if (parts.isNotEmpty) return parts.join(' · ');
  if (l.taluk.trim().isNotEmpty) return l.taluk.trim();
  if (l.district.trim().isNotEmpty) return l.district.trim();
  return 'Site #${l.leadId}';
}

/// Pin-tap details card, shown as an overlay on the map (in the outer Stack,
/// not the marker layer) so its action buttons receive taps reliably. Shows
/// the site's key details with View / Navigate actions.
class _PropertyPopup extends StatelessWidget {
  final LandLead lead;
  final VoidCallback onOpenSite;
  final VoidCallback onClose;

  const _PropertyPopup({
    required this.lead,
    required this.onOpenSite,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final acres = leadPortfolioAcres(lead);
    final villageDistrict = [
      if (lead.village.trim().isNotEmpty) lead.village.trim(),
      if (lead.district.trim().isNotEmpty) lead.district.trim(),
    ].join(', ');

    final details = <(IconData, String, String)>[
      if (lead.ownerName.trim().isNotEmpty)
        (Icons.person_outline, 'Owner', lead.ownerName.trim()),
      if (lead.surveyNumber.trim().isNotEmpty)
        (Icons.tag_rounded, 'Survey No.', lead.surveyNumber.trim()),
      if (villageDistrict.isNotEmpty)
        (Icons.location_city_outlined, 'Village', villageDistrict),
      if (lead.brokerName.trim().isNotEmpty)
        (Icons.handshake_outlined, 'Broker', lead.brokerName.trim()),
      if (lead.createdByName.trim().isNotEmpty)
        (Icons.badge_outlined, 'Executive', lead.createdByName.trim()),
      (
        Icons.event_outlined,
        'Added',
        DateFormat('dd MMM yyyy').format(lead.addedOn),
      ),
    ];

    return Material(
      color: context.fomraSurface,
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black.withValues(alpha: 0.4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.fomraBorder),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _siteName(lead),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          color: context.fomraTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Site #${lead.leadId}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.fomraTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded,
                        size: 20, color: context.fomraTextSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: lead.status.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    lead.status.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: lead.status.color,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.fomraSurfaceVar,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: context.fomraBorder),
                  ),
                  child: Text(
                    '${acres.toStringAsFixed(2)} ac',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Detail rows — two columns when the card is wide enough.
            LayoutBuilder(
              builder: (context, c) {
                final twoCol = c.maxWidth >= 340;
                const gap = 10.0;
                final cellW =
                    twoCol ? (c.maxWidth - gap) / 2 : c.maxWidth;
                return Wrap(
                  spacing: gap,
                  runSpacing: 10,
                  children: [
                    for (final d in details)
                      SizedBox(
                        width: cellW,
                        child: _detailRow(context, d.$1, d.$2, d.$3),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      // Open the lead first, then clear the pin. Closing first
                      // would null out the selected pin the navigation reads.
                      onOpenSite();
                      onClose();
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('View Details',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 42),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: lead.gpsCoordinates.trim().isEmpty
                        ? null
                        : () => MapsNavigation.navigateFromGpsString(
                              lead.gpsCoordinates,
                              label: _siteName(lead),
                            ),
                    icon: const Icon(Icons.directions_rounded, size: 18),
                    label: const Text('Navigate',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side:
                          BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: context.fomraTextSecondary),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: context.fomraTextSecondary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.fomraTextPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
