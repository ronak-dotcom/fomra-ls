import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

import 'google_satellite_tiles.dart';

/// MapTiler raster tiles (OpenMapTiles / OMT schema).
class MapTilerTiles {
  MapTilerTiles._();

  static const apiKey = String.fromEnvironment(
    'MAPTILER_API_KEY',
    defaultValue: 'MHsQC3BsvXE332lr3wT7',
  );

  static const _base = 'https://api.maptiler.com/maps';

  /// Current MapTiler streets style (PNG).
  static const standardStyle = 'streets-v4';

  /// Satellite hybrid imagery (satellite + labels, served as JPG).
  static const satelliteStyle = 'hybrid';

  static bool get isConfigured => apiKey.isNotEmpty;

  static String rasterUrl(
    String styleId, {
    String format = 'png',
  }) =>
      '$_base/$styleId/256/{z}/{x}/{y}.$format?key=$apiKey';

  static String get standard => rasterUrl(standardStyle);

  /// Google satellite when its key is set up and a session is ready; else
  /// MapTiler's satellite hybrid.
  static String get satellite =>
      GoogleSatelliteTiles.urlTemplate ??
      rasterUrl(satelliteStyle, format: 'jpg');

  /// Credit line for the layer in use.
  static String attributionFor({required bool satelliteLayer}) =>
      satelliteLayer && GoogleSatelliteTiles.urlTemplate != null
          ? GoogleSatelliteTiles.attribution
          : attribution;

  static String urlFor({required bool satelliteLayer}) =>
      satelliteLayer ? satellite : standard;

  static const attribution = '© MapTiler © OpenStreetMap contributors';

  /// Used when MapTiler is unavailable (quota, network, etc.).
  static const standardFallback =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Esri World Imagery — `{z}/{y}/{x}` tile order.
  static const satelliteFallback =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// Google's required credit, shown on a satellite map while Google
  /// imagery is in use (nothing otherwise).
  static Widget googleCredit({required bool satelliteLayer}) {
    if (!satelliteLayer || GoogleSatelliteTiles.urlTemplate == null) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: 'Google ',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: GoogleSatelliteTiles.attribution),
            ]),
            style: TextStyle(fontSize: 9, color: Colors.black87),
          ),
        ),
      ),
    );
  }

  static TileLayer tileLayer({
    required String urlTemplate,
    bool satelliteLayer = false,
    String packageName = 'in.fomrahousing.fomrals',
  }) {
    return TileLayer(
      key: ValueKey(urlTemplate),
      urlTemplate: urlTemplate,
      fallbackUrl: satelliteLayer ? satelliteFallback : standardFallback,
      userAgentPackageName: packageName,
      maxZoom: 22,
      // Cancel off-screen tile requests so the visible tiles load first — the
      // biggest perceived-speed win for flutter_map (esp. on web).
      tileProvider: CancellableNetworkTileProvider(),
      // Keep more tiles around and preload a ring so panning/first paint is
      // smoother instead of loading tile-by-tile.
      keepBuffer: 4,
      panBuffer: 1,
    );
  }
}
