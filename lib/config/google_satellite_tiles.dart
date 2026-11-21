import 'dart:convert';

import 'package:http/http.dart' as http;

/// Google satellite imagery (Map Tiles API, 2D tiles) for the satellite view.
/// On only when a key is built in (`--dart-define=GOOGLE_MAPS_KEY=…`, set from
/// the Vercel env var of the same name); otherwise MapTiler's satellite stays.
/// The street map always stays MapTiler.
///
/// Google tiles need a session token, created once and renewed before it
/// expires. Until it is ready (or if Google refuses, e.g. the daily limit is
/// reached), maps use the MapTiler / Esri satellite instead.
abstract final class GoogleSatelliteTiles {
  static const apiKey = String.fromEnvironment('GOOGLE_MAPS_KEY');

  static bool get isConfigured => apiKey.isNotEmpty;

  static String? _session;
  static DateTime? _expires;
  static Future<void>? _starting;

  /// The tile address while a session is valid, else null.
  static String? get urlTemplate {
    final s = _session;
    final exp = _expires;
    if (s == null || exp == null || DateTime.now().isAfter(exp)) {
      if (isConfigured) warmUp();
      return null;
    }
    return 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}'
        '?session=$s&key=$apiKey';
  }

  /// Google's required credit on satellite maps.
  static const attribution = 'Imagery © Google';

  /// Starts (or renews) the session in the background; safe to call often.
  static Future<void> warmUp() {
    if (!isConfigured) return Future.value();
    final exp = _expires;
    if (_session != null &&
        exp != null &&
        DateTime.now().isBefore(exp.subtract(const Duration(hours: 1)))) {
      return Future.value();
    }
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  static Future<void> _start() async {
    try {
      final res = await http
          .post(
            Uri.parse(
                'https://tile.googleapis.com/v1/createSession?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mapType': 'satellite',
              // Road and place names over the imagery, like MapTiler's hybrid.
              'layerTypes': ['layerRoadmap'],
              'language': 'en-IN',
              'region': 'IN',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final session = body['session'] as String?;
      final expiry = int.tryParse('${body['expiry'] ?? ''}');
      if (session == null || session.isEmpty) return;
      _session = session;
      // Expiry is in seconds since 1970; renew a day early.
      _expires = expiry == null
          ? DateTime.now().add(const Duration(days: 7))
          : DateTime.fromMillisecondsSinceEpoch(expiry * 1000)
              .subtract(const Duration(days: 1));
    } catch (_) {
      // Stay on MapTiler satellite.
    }
  }
}
