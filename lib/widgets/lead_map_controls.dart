import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/maptiler_tiles.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import 'map_layer_toggle.dart';

/// Small floating +/- zoom buttons for a [FlutterMap], plus an optional
/// expand/fullscreen button — used on every inline lead-location map so
/// zoom/expand behavior looks and feels the same everywhere.
class MapZoomControls extends StatelessWidget {
  final MapController controller;
  final VoidCallback? onExpand;

  const MapZoomControls({super.key, required this.controller, this.onExpand});

  void _zoom(double delta) {
    final camera = controller.camera;
    controller.move(camera.center, (camera.zoom + delta).clamp(3.0, 22.0));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(Icons.add, () => _zoom(1)),
        const SizedBox(height: 6),
        _btn(Icons.remove, () => _zoom(-1)),
        if (onExpand != null) ...[
          const SizedBox(height: 6),
          _btn(Icons.open_in_full_rounded, onExpand!),
        ],
      ],
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 3,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
      ),
    );
  }
}

/// Pushes a full-screen map view. Pass [onTap] to allow repositioning the pin
/// (Add/Edit Lead); leave it null for a read-only view (View Lead). Has its
/// own Standard/Satellite toggle, independent of whatever layer the caller
/// happened to be showing.
Future<void> showFullscreenLeadMap(
  BuildContext context, {
  required LatLng initialCenter,
  double initialZoom = 16,
  LatLng? pinnedPoint,
  Future<void> Function(LatLng)? onTap,
  String title = 'Location',
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FullscreenLeadMap(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        pinnedPoint: pinnedPoint,
        onTap: onTap,
        title: title,
      ),
    ),
  );
}

class _FullscreenLeadMap extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final LatLng? pinnedPoint;
  final Future<void> Function(LatLng)? onTap;
  final String title;

  const _FullscreenLeadMap({
    required this.initialCenter,
    required this.initialZoom,
    required this.pinnedPoint,
    required this.onTap,
    required this.title,
  });

  @override
  State<_FullscreenLeadMap> createState() => _FullscreenLeadMapState();
}

class _FullscreenLeadMapState extends State<_FullscreenLeadMap> {
  final _controller = MapController();
  late LatLng? _pinnedPoint = widget.pinnedPoint;
  bool _updating = false;
  bool _satelliteLayer = false;

  bool get _readOnly => widget.onTap == null;

  Future<void> _handleTap(LatLng point) async {
    if (_readOnly) return;
    setState(() {
      _pinnedPoint = point;
      _updating = true;
    });
    try {
      await widget.onTap!(point);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              onTap: _readOnly ? null : (_, point) => _handleTap(point),
            ),
            children: [
              MapTilerTiles.tileLayer(
                urlTemplate:
                    MapTilerTiles.urlFor(satelliteLayer: _satelliteLayer),
                satelliteLayer: _satelliteLayer,
              ),
              MapTilerTiles.googleCredit(satelliteLayer: _satelliteLayer),
              if (_pinnedPoint != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _pinnedPoint!,
                    width: 44,
                    height: 52,
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFFE53935),
                      size: 44,
                    ),
                  ),
                ]),
            ],
          ),
          Positioned(
            left: 16,
            top: 16,
            child: MapLayerToggle(
              satellite: _satelliteLayer,
              onChanged: (v) => setState(() => _satelliteLayer = v),
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: MapZoomControls(controller: _controller),
          ),
          if (_updating)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// Read-only "Location" card for View Lead — a small map preview with zoom
/// and expand controls, centered on the lead's pinned GPS point.
class LeadLocationMapCard extends StatefulWidget {
  final LatLng point;
  final String tileUrl;
  final String title;

  const LeadLocationMapCard({
    super.key,
    required this.point,
    required this.tileUrl,
    this.title = 'Location',
  });

  @override
  State<LeadLocationMapCard> createState() => _LeadLocationMapCardState();
}

class _LeadLocationMapCardState extends State<LeadLocationMapCard> {
  final _controller = MapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openFullscreen() {
    showFullscreenLeadMap(
      context,
      initialCenter: widget.point,
      pinnedPoint: widget.point,
      title: widget.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.fomraSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.fomraBorder),
        boxShadow: context.fomraCardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, size: 15, color: AppColors.purple),
              const SizedBox(width: 7),
              Text(
                'Location',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: context.fomraTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 160,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _controller,
                    options: MapOptions(
                      initialCenter: widget.point,
                      initialZoom: 16,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: widget.tileUrl,
                        userAgentPackageName: 'in.fomrahousing.fomrals',
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: widget.point,
                          width: 36,
                          height: 42,
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Color(0xFFE53935),
                            size: 36,
                          ),
                        ),
                      ]),
                    ],
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: MapZoomControls(
                      controller: _controller,
                      onExpand: _openFullscreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
