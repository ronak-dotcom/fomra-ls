import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/maptiler_tiles.dart';
import '../../models/competitor_project.dart';
import '../../models/land_lead.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/competitor_analysis.dart';
import '../../utils/lead_location_parser.dart';
import '../../widgets/map_layer_toggle.dart';
import 'competitor_widgets.dart';

/// Competitor projects (price pins coloured by stage) with our leads as blue
/// pins. On a lead page, [focusLead] is the red pin and [radiusKm] draws the
/// search circle around it. Tapping a project shows a small card.
class CompetitorMap extends StatefulWidget {
  final List<CompetitorProject> projects;
  final List<LandLead> leads;
  final LandLead? focusLead;
  final double? radiusKm;
  final ValueChanged<CompetitorProject> onOpenProject;
  final ValueChanged<LandLead>? onOpenLead;

  const CompetitorMap({
    super.key,
    required this.projects,
    this.leads = const [],
    this.focusLead,
    this.radiusKm,
    required this.onOpenProject,
    this.onOpenLead,
  });

  @override
  State<CompetitorMap> createState() => _CompetitorMapState();
}

class _CompetitorMapState extends State<CompetitorMap> {
  bool _satellite = true;
  CompetitorProject? _selected;

  LatLng? get _focus =>
      widget.focusLead == null ? null : parseLeadGps(widget.focusLead!.gpsCoordinates);

  /// Centre and zoom that fit every pin (or the radius circle).
  (LatLng, double) _initialView() {
    final pts = <LatLng>[
      for (final p in widget.projects)
        if (p.point != null) p.point!,
      if (_focus != null) _focus!,
    ];
    if (widget.focusLead == null) {
      for (final l in widget.leads) {
        final pin = parseLeadGps(l.gpsCoordinates);
        if (pin != null) pts.add(pin);
      }
    }
    if (pts.isEmpty) return (const LatLng(12.92, 80.05), 10);
    if (_focus != null && widget.radiusKm != null) {
      // Fit the circle: ~zoom for the radius at this latitude.
      final z = 14.2 - math.log(widget.radiusKm!) / math.ln2;
      return (_focus!, z.clamp(8, 16).toDouble());
    }
    var minLat = pts.first.latitude, maxLat = minLat;
    var minLng = pts.first.longitude, maxLng = minLng;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    final centre = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final span = math.max(maxLat - minLat, maxLng - minLng);
    final zoom = span <= 0 ? 14.0 : (8.6 - math.log(span) / math.ln2).clamp(7, 16);
    return (centre, zoom.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final view = _initialView();
    final focus = _focus;
    final plotted = [
      for (final p in widget.projects)
        if (p.point != null) p,
    ];
    final leadPins = [
      for (final l in widget.leads)
        if (l.leadId != widget.focusLead?.leadId &&
            parseLeadGps(l.gpsCoordinates) != null)
          (l, parseLeadGps(l.gpsCoordinates)!),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(children: [
        FlutterMap(
          key: ValueKey('${widget.focusLead?.leadId}-${widget.radiusKm}'),
          options: MapOptions(
            initialCenter: view.$1,
            initialZoom: view.$2,
            onTap: (_, __) => setState(() => _selected = null),
          ),
          children: [
            MapTilerTiles.tileLayer(
              urlTemplate: MapTilerTiles.urlFor(satelliteLayer: _satellite),
              satelliteLayer: _satellite,
            ),
            MapTilerTiles.googleCredit(satelliteLayer: _satellite),
            if (focus != null && widget.radiusKm != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: focus,
                  radius: widget.radiusKm! * 1000,
                  useRadiusInMeter: true,
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderColor: AppColors.primary.withValues(alpha: 0.7),
                  borderStrokeWidth: 1.5,
                ),
              ]),
            MarkerLayer(markers: [
              for (final (l, pin) in leadPins)
                Marker(
                  point: pin,
                  width: OurLeadPin.width,
                  height: OurLeadPin.height,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: widget.onOpenLead == null
                        ? null
                        : () => widget.onOpenLead!(l),
                    child: OurLeadPin(label: '#${l.leadId}'),
                  ),
                ),
              if (focus != null)
                Marker(
                  point: focus,
                  width: OurLeadPin.width,
                  height: OurLeadPin.height,
                  alignment: Alignment.topCenter,
                  child: OurLeadPin(
                      label: '#${widget.focusLead!.leadId}', highlight: true),
                ),
              for (final p in plotted)
                Marker(
                  point: p.point!,
                  width: CompetitorPricePin.width,
                  height: CompetitorPricePin.height,
                  alignment: Alignment.topCenter,
                  child: CompetitorPricePin(
                    project: p,
                    selected: _selected?.id == p.id,
                    onTap: () => setState(() => _selected = p),
                  ),
                ),
            ]),
          ],
        ),
        Positioned(
          left: 10,
          top: 10,
          child: MapLayerToggle(
            satellite: _satellite,
            onChanged: (v) => setState(() => _satellite = v),
          ),
        ),
        Positioned(
          right: 10,
          top: 10,
          child: _Legend(showFocus: focus != null),
        ),
        if (_selected != null)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _PinCard(
                  project: _selected!,
                  km: focus != null && _selected!.point != null
                      ? kmBetween(focus, _selected!.point!)
                      : null,
                  onOpen: () => widget.onOpenProject(_selected!),
                  onClose: () => setState(() => _selected = null),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final bool showFocus;
  const _Legend({required this.showFocus});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(t,
                style: TextStyle(fontSize: 10.5, color: context.fomraTextPrimary)),
          ]),
        );
    return Material(
      color: context.fomraSurface.withValues(alpha: 0.93),
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final s in CompetitorStage.values) dot(s.color, s.label),
          dot(const Color(0xFF0EA5E9), 'Our leads'),
          if (showFocus) dot(AppColors.error, 'This lead'),
        ]),
      ),
    );
  }
}

class _PinCard extends StatelessWidget {
  final CompetitorProject project;
  final double? km;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  const _PinCard({
    required this.project,
    required this.km,
    required this.onOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    return Material(
      color: context.fomraSurface,
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${p.code} · ${p.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (p.builder.isNotEmpty) p.builder,
                    p.stage.label,
                    if (p.dealPrice != null) '${rupees(p.dealPrice)}/sq ft',
                    if (km != null) '${km!.toStringAsFixed(1)} km away',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, color: context.fomraTextSecondary),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onOpen, child: const Text('Open')),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ]),
      ),
    );
  }
}
