import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/maptiler_tiles.dart';
import '../../models/land_lead.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_input.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/lead_location_parser.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/fmb_sketch_viewer.dart';
import '../../widgets/market_intelligence_ui.dart';
import '../../widgets/patta_document_preview.dart';
import '../../widgets/patta_html_preview.dart';
import '../../widgets/portal_home_sections.dart';
import '../../widgets/portal_page_layout.dart';
import '../../widgets/tngis_parcel_summary.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../utils/tngis_parcel_lookup.dart';

// â”€â”€ POI category definitions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PoiCategory {
  final String name;
  final IconData icon;
  final Color color;
  final String tag;
  final String value;
  const _PoiCategory(this.name, this.icon, this.color, this.tag, this.value);
}

enum _MarketMapLayer { standard, satellite }

const _kCategories = [
  _PoiCategory('Schools', Icons.school_outlined, Color(0xFF1565C0), 'amenity', 'school'),
  _PoiCategory('Colleges', Icons.school, Color(0xFF0D47A1), 'amenity', 'college'),
  _PoiCategory('Universities', Icons.account_balance_outlined, Color(0xFF1A237E), 'amenity', 'university'),
  _PoiCategory('Hospitals', Icons.local_hospital_outlined, Color(0xFFD32F2F), 'amenity', 'hospital'),
  _PoiCategory('Clinics', Icons.medical_services_outlined, Color(0xFFE53935), 'amenity', 'clinic'),
  _PoiCategory('Pharmacies', Icons.local_pharmacy_outlined, Color(0xFFC62828), 'amenity', 'pharmacy'),
  _PoiCategory('Bus Stops', Icons.directions_bus_outlined, Color(0xFF1B5E20), 'highway', 'bus_stop'),
  _PoiCategory('Bus Terminals', Icons.directions_bus_filled_outlined, Color(0xFF2E7D32), 'amenity', 'bus_station'),
  _PoiCategory('Railway Stations', Icons.train_outlined, Color(0xFF37474F), 'railway', 'station'),
  _PoiCategory('Metro Stations', Icons.subway_outlined, Color(0xFF4527A0), 'station', 'subway'),
  _PoiCategory('Airports', Icons.flight_outlined, Color(0xFF0277BD), 'aeroway', 'aerodrome'),
  _PoiCategory('Supermarkets', Icons.shopping_cart_outlined, Color(0xFF6A1B9A), 'shop', 'supermarket'),
  _PoiCategory('Malls', Icons.local_mall_outlined, Color(0xFFAD1457), 'shop', 'mall'),
  _PoiCategory('Banks', Icons.account_balance_outlined, Color(0xFFE65100), 'amenity', 'bank'),
  _PoiCategory('Restaurants', Icons.restaurant_outlined, Color(0xFFBF360C), 'amenity', 'restaurant'),
  _PoiCategory('ATMs', Icons.atm_outlined, Color(0xFFF57C00), 'amenity', 'atm'),
  _PoiCategory('IT Parks', Icons.computer_outlined, Color(0xFF006064), 'office', 'it'),
  _PoiCategory('Petrol Stations', Icons.local_gas_station_outlined, Color(0xFF558B2F), 'amenity', 'fuel'),
  _PoiCategory('Govt. Offices', Icons.account_balance_wallet_outlined, Color(0xFF795548), 'amenity', 'townhall'),
  _PoiCategory('Worship Places', Icons.temple_hindu_outlined, Color(0xFF880E4F), 'amenity', 'place_of_worship'),
];

/// Overall infrastructure weights from idea.txt
const _kInfraCategoryOrder = [
  'Education',
  'Healthcare',
  'Road Connectivity',
  'Commercial',
  'Transport',
];

// â”€â”€ Valuation result â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AreaPriceStats {
  final double avgPerSqft;
  final double medianPerSqft;
  final int pricedCount;

  const _AreaPriceStats({
    required this.avgPerSqft,
    required this.medianPerSqft,
    required this.pricedCount,
  });

  bool get hasData => pricedCount > 0;
}

class _ValuationResult {
  final double areaAvgPerSqft;
  final int pricedListingCount;
  final double landSizeSqft;
  final double buyPerSqft;
  final double sellPerSqft;
  final double recommendedPurchasePrice;
  final double recommendedSellingPrice;
  final double expectedMargin;
  final int investmentScore;
  final int riskScore;
  final String recommendation;
  final String investmentReason;
  final String riskReason;

  _ValuationResult({
    required this.areaAvgPerSqft,
    required this.pricedListingCount,
    required this.landSizeSqft,
    required this.buyPerSqft,
    required this.sellPerSqft,
    required this.recommendedPurchasePrice,
    required this.recommendedSellingPrice,
    required this.expectedMargin,
    required this.investmentScore,
    required this.riskScore,
    required this.recommendation,
    this.investmentReason = '',
    this.riskReason = '',
  });
}

String _fmtIndianRupee(double value) {
  if (value >= 1e7) return '₹${(value / 1e7).toStringAsFixed(2)} Cr';
  if (value >= 1e5) return '₹${(value / 1e5).toStringAsFixed(2)} L';
  if (value >= 1000) return '₹${(value / 1000).toStringAsFixed(1)}K';
  return '₹${value.round()}';
}

/// When [embeddedInLead] is true, show only this section (lead detail tabs).
enum MarketIntelLeadSection {
  infrastructure,
  landRecords,
  competitorProjects,
}

// â”€â”€ Main Screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class MarketIntelligenceScreen extends StatefulWidget {
  final LandLead? lead;
  final bool embeddedInLead;
  final MarketIntelLeadSection? leadSectionOnly;

  /// When false, the embedded lead section renders at its natural height with
  /// no internal scroll view, so it can participate in a single outer page
  /// scroll (used by the lead detail workspace).
  final bool embeddedScrollable;

  const MarketIntelligenceScreen({
    super.key,
    this.lead,
    this.embeddedInLead = false,
    this.leadSectionOnly,
    this.embeddedScrollable = true,
  });

  @override
  State<MarketIntelligenceScreen> createState() =>
      _MarketIntelligenceScreenState();
}

class _MarketIntelligenceScreenState extends State<MarketIntelligenceScreen> {
  // Location â€“ GPS
  Position? _position;
  bool _fetchingLocation = false;
  String? _locationError;
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _mapFullScreen = false;
  _MarketMapLayer _mapLayer = _MarketMapLayer.standard;
  LatLng? _tappedPoint;

  // Location â€“ Search
  final bool _searchMode = false;
  LatLng? _searchedLocation;
  bool _searchingLocation = false;
  String? _searchError;
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;
  Timer? _searchDebounce;

  // POI
  int _selectedRadius = 2;
  int _compRadiusKm = 2;
  Map<String, int> _poiCounts = {};
  Map<String, List<Map<String, dynamic>>> _poiPlaces = {};
  bool _collectingPois = false;
  String? _poiError;
  bool _poisCollected = false;
  Map<String, double> _infraScoreMap = {};
  int _poiFetchSeq = 0;
  int _tngisFetchSeq = 0;

  // Valuation inputs
  final _roadWidthCtrl = TextEditingController();
  final _landSizeCtrl = TextEditingController();
  _ValuationResult? _valuationResult;

  // Competitor Projects (SquareYards + NoBroker)
  List<Map<String, dynamic>> _mbListings = [];
  bool _fetchingMb = false;
  String? _mbError;
  String? _mbPartialWarning;
  String _mbSource = 'SquareYards + NoBroker';
  String _typeFilter = 'All';   // Layer 1: All | House | Plot | Flat
  String _stageFilter = 'All';  // Layer 2: All | Ongoing | Completed | Old
  int _oldYearsFilter = 5;       // 2 | 5 | 10
  bool _projectsExpanded = false; // collapsed until user taps summary bar
  int _mbFetchSeq = 0;

  // EC & Patta – location data passed to the section widget
  String? _detectedDistrict;
  String? _detectedTaluk;
  String? _detectedVillage;
  String? _tngisSurvey;
  String? _tngisSubDiv;
  String? _tngisDc;
  String? _tngisTc;
  String? _tngisVc;
  String? _tngisRuralUrban;
  String? _tngisGiViewerUrl;
  Map<String, dynamic>? _tngisGiServices;
  String? _tngisUlpin;
  String? _tngisCentroid;
  bool _tngisParcelLoading = false;
  String? _tngisParcelError;
  List<_TngisSubdivisionRow> _tngisSubdivisions = [];
  bool _tngisFmbAvailable = false;
  String? _tngisFmbNote;

  // Lead detail mode — location from saved lead GPS
  LatLng? _leadLocation;
  bool _geocodingLead = false;

  // Default center shown before GPS resolves
  static const _kDefaultCenter = LatLng(13.0827, 80.2707);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.embeddedInLead && widget.lead != null) {
        _initializeFromLead(widget.lead!);
      } else {
        _detectLocation();
      }
    });
  }

  @override
  void dispose() {
    _roadWidthCtrl.dispose();
    _landSizeCtrl.dispose();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // â”€â”€ Active location (GPS or searched) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  LatLng? get _activeLatLng =>
      _searchedLocation ??
      _leadLocation ??
      (_position != null
          ? LatLng(_position!.latitude, _position!.longitude)
          : null);

  Future<void> _initializeFromLead(LandLead lead) async {
    final loc = parseLeadGps(lead.gpsCoordinates);
    final roadFt = parseRoadWidthFt(lead.roadWidth);
    final sqft = parseLandExtentSqft(lead.landExtent);

    if (roadFt != null) {
      _roadWidthCtrl.text = roadFt.toStringAsFixed(0);
    }
    if (sqft != null) {
      _landSizeCtrl.text = sqft.round().toString();
    }


    setState(() {
      _leadLocation = loc;
      _detectedDistrict =
          lead.district.isNotEmpty ? lead.district : _detectedDistrict;
      _detectedTaluk = lead.taluk.isNotEmpty ? lead.taluk : _detectedTaluk;
      _detectedVillage =
          lead.village.isNotEmpty ? lead.village : _detectedVillage;
      if (lead.surveyNumber.isNotEmpty) {
        _tngisSurvey = lead.surveyNumber;
      }
      if (lead.subDivision.isNotEmpty) {
        _tngisSubDiv = lead.subDivision;
      }
    });

    if (loc != null) {
      _fetchLocationDetails(loc);
      _fetchLeadSectionData(loc);
    } else {
      _maybeGeocodeLeadLocation(lead);
    }
  }

  bool get _needsInfrastructureData =>
      widget.leadSectionOnly == null ||
      widget.leadSectionOnly == MarketIntelLeadSection.infrastructure;

  bool get _needsLandRecordsData =>
      widget.leadSectionOnly == null ||
      widget.leadSectionOnly == MarketIntelLeadSection.landRecords;

  bool get _needsCompetitorData =>
      widget.leadSectionOnly == null ||
      widget.leadSectionOnly == MarketIntelLeadSection.competitorProjects;

  void _fetchLeadSectionData(LatLng loc) {
    if (_needsLandRecordsData) {
      _fetchTngisParcelDetails(loc);
    }
    if (_needsInfrastructureData) {
      _collectPois();
    }
    if (_needsCompetitorData) {
      _fetchMagicBricksProjects();
    }
  }

  void _maybeGeocodeLeadLocation(LandLead lead) {
    if (!_needsInfrastructureData && !_needsCompetitorData) return;
    _geocodeLeadLocation(lead);
  }

  /// Falls back to geocoding the lead's address text (village/taluk/district)
  /// when no GPS coordinates were saved, so the map can still show the area.
  Future<void> _geocodeLeadLocation(LandLead lead) async {
    final parts = [
      lead.village,
      lead.taluk,
      lead.district,
      lead.pincode,
    ].where((p) => p.trim().isNotEmpty).toList();
    final query = (parts.isNotEmpty ? parts.join(', ') : lead.location).trim();
    if (query.isEmpty) return;

    setState(() => _geocodingLead = true);
    try {
      final response = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent('$query, Tamil Nadu, India')}&limit=1'),
        headers: {
          'User-Agent': 'FomraLS/1.0 (in.fomrahousing)',
          'Accept-Language': 'en',
        },
      );
      if (response.statusCode == 200) {
        final results = jsonDecode(response.body) as List;
        if (results.isNotEmpty) {
          final r = results.first as Map<String, dynamic>;
          final lat = double.tryParse(r['lat'] as String? ?? '');
          final lon = double.tryParse(r['lon'] as String? ?? '');
          if (lat != null && lon != null && mounted) {
            final loc = LatLng(lat, lon);
            setState(() => _leadLocation = loc);
            _fetchLeadSectionData(loc);
          }
        }
      }
    } catch (_) {
      // Leave the "no location" message in place on failure.
    } finally {
      if (mounted) setState(() => _geocodingLead = false);
    }
  }

  void _tryAutoValuation() {
    if (!widget.embeddedInLead) return;
    if (!_poisCollected || !_areaPriceStats().hasData) return;
    final result = _computeValuation();
    if (result != null && mounted) {
      setState(() => _valuationResult = result);
    }
  }

  // â”€â”€ GPS Location â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _detectLocation() async {
    setState(() {
      _fetchingLocation = true;
      _locationError = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled. Enable GPS in device settings.');
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied. Enable it in App Settings.');
      }
      if (perm == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() => _position = pos);
      if (_mapReady) {
        _mapController.move(
            LatLng(pos.latitude, pos.longitude), _zoomForRadius(_selectedRadius));
      }
      _fetchLocationDetails(LatLng(pos.latitude, pos.longitude));
      _collectPois();
      _fetchMagicBricksProjects();
    } catch (e) {
      setState(() =>
          _locationError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _fetchingLocation = false);
    }
  }

  // â”€â”€ Location Search (Nominatim) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // Live suggestions as the user types — even a single character. Debounced so
  // we don't hit Nominatim on every keystroke.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _searchError = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _suggestLocations(q);
    });
  }

  Future<void> _suggestLocations(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    // Bias results to the area currently in view (or Tamil Nadu) so short
    // queries surface nearby places first, without hard-restricting them.
    final center = _activeLatLng ?? _searchedLocation;
    String viewbox = '';
    if (center != null) {
      const d = 0.75; // ~80km box around the current centre
      viewbox = '&viewbox=${center.longitude - d},${center.latitude + d},'
          '${center.longitude + d},${center.latitude - d}';
    }

    try {
      final response = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(q)}'
            '&limit=8&addressdetails=1&countrycodes=in$viewbox'),
        headers: {
          'User-Agent': 'FomraLS/1.0 (in.fomrahousing)',
          'Accept-Language': 'en',
        },
      );
      // Ignore stale responses if the box has been cleared/changed meanwhile.
      if (!mounted || _searchCtrl.text.trim() != q) return;
      if (response.statusCode == 200) {
        final results = (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
        setState(() {
          _searchResults = results;
          _showSearchResults = results.isNotEmpty;
          _searchError = null;
        });
      }
    } catch (_) {
      // Silent for live suggestions — the Search button surfaces hard errors.
    }
  }

  Future<void> _searchLocation(String query) async {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) return;
    setState(() {
      _searchingLocation = true;
      _searchError = null;
      _searchResults = [];
      _showSearchResults = false;
    });
    try {
      final response = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query.trim())}&limit=5&addressdetails=1'),
        headers: {
          'User-Agent': 'FomraLS/1.0 (in.fomrahousing)',
          'Accept-Language': 'en',
        },
      );
      if (response.statusCode == 200) {
        final results = jsonDecode(response.body) as List;
        setState(() {
          _searchResults = results.cast<Map<String, dynamic>>();
          _showSearchResults = _searchResults.isNotEmpty;
          if (_searchResults.isEmpty) {
            _searchError = 'No results found. Try a different search.';
          }
        });
      } else {
        setState(() => _searchError = 'Search failed. Check your connection.');
      }
    } catch (_) {
      setState(() => _searchError = 'No internet connection.');
    } finally {
      setState(() => _searchingLocation = false);
    }
  }

  void _selectSearchResult(Map<String, dynamic> result) {
    final lat = double.tryParse(result['lat'] as String? ?? '') ?? 0;
    final lon = double.tryParse(result['lon'] as String? ?? '') ?? 0;
    final name = result['display_name'] as String? ?? 'Searched Location';
    final loc = LatLng(lat, lon);
    setState(() {
      _searchedLocation = loc;
      _showSearchResults = false;
      _searchCtrl.text = name.split(',').first.trim();
      _poisCollected = false;
      _poiCounts = {};
      _poiPlaces = {};
      _infraScoreMap = {};
      _valuationResult = null;
      _tngisSurvey = null;
      _tngisSubDiv = null;
      _tngisRuralUrban = null;
      _tngisDc = null;
      _tngisTc = null;
      _tngisVc = null;
      _tngisGiServices = null;
      _tngisUlpin = null;
      _tngisCentroid = null;
      _tngisSubdivisions = [];
      _tngisFmbAvailable = false;
      _tngisFmbNote = null;
    });
    if (_mapReady) {
      _mapController.move(_searchedLocation!, _zoomForRadius(_selectedRadius));
    }
    _fetchLocationDetails(loc);
    _collectPois();
    _fetchMagicBricksProjects();
  }

  void _handleMapTap(LatLng point) {
    setState(() {
      _searchedLocation = point;
      _tappedPoint = null;
      _poisCollected = false;
      _poiCounts = {};
      _poiPlaces = {};
      _infraScoreMap = {};
      _valuationResult = null;
      _detectedDistrict = null;
      _detectedTaluk = null;
      _detectedVillage = null;
      _tngisSurvey = null;
      _tngisSubDiv = null;
      _tngisRuralUrban = null;
      _tngisDc = null;
      _tngisTc = null;
      _tngisVc = null;
      _tngisUlpin = null;
      _tngisCentroid = null;
      _tngisGiViewerUrl = null;
      _tngisGiServices = null;
      _tngisSubdivisions = [];
      _tngisFmbAvailable = false;
      _tngisFmbNote = null;
      _tngisParcelLoading = true;
      _tngisParcelError = null;
    });
    if (_mapReady) {
      _mapController.move(point, _mapController.camera.zoom);
    }
    _fetchLocationDetails(point);
    _fetchTngisParcelDetails(point);
    _collectPois();
    _fetchMagicBricksProjects();
  }

  /// Parse sub-division from TNGIS (often in kide e.g. 394/15C).
  String? _parseTngisSubDivision(String? subDiv, String? kide, String? survey) {
    final s = subDiv?.trim();
    final surveyTrim = survey?.trim() ?? '';
    if (s != null && s.isNotEmpty && s != '-' && s != surveyTrim) return s;
    final k = kide?.trim();
    if (k == null || k.isEmpty || k == '0' || !k.contains('/')) return null;
    final parts = k.split('/');
    if (parts.length < 2) return null;
    final kideSub = parts.sublist(1).join('/').trim();
    if (kideSub.isEmpty || kideSub == '-' || kideSub == surveyTrim) return null;
    final kideSurvey = parts[0].trim();
    if (surveyTrim.isNotEmpty && kideSurvey.isNotEmpty && kideSurvey != surveyTrim) {
      return null;
    }
    return kideSub;
  }

  /// Fetch survey no & sub-division from TNGIS for the tapped map point.
  Future<void> _fetchTngisParcelDetails(LatLng loc) async {
    final fetchSeq = ++_tngisFetchSeq;
    setState(() {
      _tngisParcelLoading = true;
      _tngisParcelError = null;
    });
    try {
      final params = <String, String>{
        'lat': loc.latitude.toString(),
        'lon': loc.longitude.toString(),
      };

      final query = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final path = '/api/tnlands/tngis/parcel?$query';
      Map<String, dynamic>? result;
      ApiException? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          result = await ApiClient.get(
            path,
            timeout: const Duration(seconds: 90),
          );
          lastError = null;
          break;
        } on ApiException catch (e) {
          lastError = e;
          final retryable = e.statusCode == 408 ||
              e.statusCode == 500 ||
              e.statusCode == 502 ||
              e.statusCode == 503 ||
              e.statusCode == 504;
          if (!retryable || attempt == 2) rethrow;
          await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      }
      if (result == null) throw lastError ?? Exception('TNGIS lookup failed');
      if (!mounted || fetchSeq != _tngisFetchSeq) return;
      final data = result;
      final fields = (data['fields'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString()));
      final survey = (data['surveyNumber'] ?? fields['Survey Number'])?.toString();
      final kideRaw = data['kide']?.toString() ?? fields['Kide'];
      final subdivisions = ((data['subdivisions'] as List<dynamic>? ?? [])
          .map((e) => _TngisSubdivisionRow.fromJson(e as Map<String, dynamic>))
          .where((r) => r.surveyNumber.isNotEmpty)
          .toList());

      // Sub at map point — prefer view_fmb subdivision polygon containing the tap.
      String? resolvedSub;
      String? resolvedKide = kideRaw;
      for (final row in subdivisions) {
        if (row.containsPoint && row.effectiveSubDivision != null) {
          resolvedSub = row.effectiveSubDivision;
          resolvedKide = row.kide ?? resolvedKide;
          break;
        }
      }
      resolvedSub ??= _parseTngisSubDivision(
        (data['subDivision'] ?? fields['Sub Division'])?.toString(),
        resolvedKide,
        survey,
      );

      String? pickAdmin(String? primary, String? fallback) {
        final p = primary?.trim();
        if (p != null && p.isNotEmpty) return p;
        final f = fallback?.trim();
        if (f != null && f.isNotEmpty && f != '-') return f;
        return null;
      }

      setState(() {
        _tngisGiViewerUrl = data['giViewerUrl'] as String?;
        _tngisGiServices = (data['giServices'] as Map?)?.cast<String, dynamic>();
        _tngisUlpin = data['ulpin']?.toString();
        _tngisCentroid = data['centroid']?.toString();
        _tngisSurvey = survey?.isNotEmpty == true ? survey : null;
        _tngisSubDiv = resolvedSub;
        _tngisDc = fields['District Code'];
        _tngisTc = fields['Taluk Code'];
        _tngisVc = fields['Village Code'];
        _tngisRuralUrban = data['ruralUrban']?.toString();
        _detectedDistrict = pickAdmin(
          data['district'] as String?,
          fields['District'],
        );
        _detectedTaluk = pickAdmin(
          data['taluk'] as String?,
          fields['Taluk'],
        );
        _detectedVillage = pickAdmin(
          data['village'] as String?,
          fields['Village'],
        );
        _tngisParcelError = null;
        _tngisFmbAvailable = data['fmbAvailable'] == true;
        _tngisFmbNote = data['fmbNote']?.toString();
        _tngisSubdivisions = _TngisSubdivisionRow.filterForTap(
          subdivisions,
          resolvedSub,
          survey,
        );
        if (_tngisSubdivisions.isEmpty && _tngisSurvey != null) {
          _tngisSubdivisions = [
            _TngisSubdivisionRow(
              surveyNumber: _tngisSurvey!,
              subDivision: _tngisSubDiv,
              kide: (resolvedKide != null && resolvedKide.isNotEmpty && resolvedKide != '0')
                  ? resolvedKide
                  : null,
              fields: fields,
              containsPoint: data['containsPoint'] == true || _tngisSubDiv != null,
              fmbAvailable: data['fmbAvailable'] == true,
            ),
          ];
        }
      });
    } on ApiException catch (e) {
      if (!mounted || fetchSeq != _tngisFetchSeq) return;
      setState(() {
        _tngisParcelError = e.message;
        _tngisGiServices = null;
        _tngisUlpin = null;
        _tngisCentroid = null;
        _tngisSubdivisions = [];
        _tngisFmbAvailable = false;
        _tngisFmbNote = null;
      });
    } catch (e) {
      if (!mounted || fetchSeq != _tngisFetchSeq) return;
      setState(() {
        _tngisParcelError = e.toString().replaceAll('Exception: ', '');
        _tngisGiServices = null;
        _tngisUlpin = null;
        _tngisCentroid = null;
        _tngisSubdivisions = [];
        _tngisFmbAvailable = false;
        _tngisFmbNote = null;
      });
    } finally {
      if (mounted && fetchSeq == _tngisFetchSeq) {
        setState(() => _tngisParcelLoading = false);
      }
    }
  }

  // â”€â”€ POI Collection via Overpass API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _collectPois() async {
    final loc = _activeLatLng;
    if (loc == null) return;
    final requestLat = loc.latitude;
    final requestLon = loc.longitude;
    final requestRadius = _selectedRadius;
    final fetchSeq = ++_poiFetchSeq;
    final hadScores = _poisCollected;
    setState(() {
      _collectingPois = true;
      _poiError = null;
      if (!hadScores) {
        _poiCounts = {};
        _poiPlaces = {};
        _infraScoreMap = {};
        _poisCollected = false;
      }
    });

    try {
      final roadFt = parseRoadWidthFt(widget.lead?.roadWidth ?? '') ??
          double.tryParse(_roadWidthCtrl.text);

      final data = await ApiClient.post(
        '/api/poi/infrastructure',
        {
          'lat': requestLat,
          'lon': requestLon,
          'radiusKm': requestRadius,
          if (roadFt != null) 'roadWidthFt': roadFt,
        },
        auth: false,
      ).timeout(const Duration(seconds: 35));

      if (!mounted || fetchSeq != _poiFetchSeq) return;

      final countsRaw = (data['counts'] as Map?)?.cast<String, dynamic>() ?? {};
      final placesRaw = (data['places'] as Map?)?.cast<String, dynamic>() ?? {};
      final scoresRaw = (data['scores'] as Map?)?.cast<String, dynamic>() ?? {};

      final counts = <String, int>{};
      for (final cat in _kCategories) {
        counts[cat.name] = (countsRaw[cat.name] as num?)?.toInt() ?? 0;
      }

      final places = <String, List<Map<String, dynamic>>>{};
      for (final cat in _kCategories) {
        final list = placesRaw[cat.name] as List<dynamic>? ?? [];
        places[cat.name] = list.map((e) {
          final m = (e as Map).cast<String, dynamic>();
          return <String, dynamic>{
            'name': m['name']?.toString() ?? 'Unnamed',
            if (m['lat'] != null) 'lat': (m['lat'] as num).toDouble(),
            if (m['lon'] != null) 'lon': (m['lon'] as num).toDouble(),
            if (m['distance'] != null) 'distance': (m['distance'] as num).toDouble(),
          };
        }).toList();
      }

      final scores = <String, double>{};
      for (final entry in scoresRaw.entries) {
        scores[entry.key] = (entry.value as num).toDouble();
      }

      setState(() {
        _poiCounts = counts;
        _poiPlaces = places;
        _infraScoreMap = scores;
        _poisCollected = scores.isNotEmpty;
      });
    } on ApiException catch (e) {
      if (!mounted || fetchSeq != _poiFetchSeq) return;
      final hint = e.statusCode == 404
          ? ' Restart the backend (npm start in backend/) and hard-refresh the page.'
          : '';
      setState(() => _poiError = 'Infrastructure fetch failed: ${e.message}.$hint');
    } catch (e) {
      if (!mounted || fetchSeq != _poiFetchSeq) return;
      setState(() => _poiError =
          'Infrastructure fetch failed: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted && fetchSeq == _poiFetchSeq) {
        setState(() => _collectingPois = false);
        _tryAutoValuation();
      }
    }
  }

  Map<String, double> get _infraScores =>
      _poisCollected ? _infraScoreMap : {};

  // â”€â”€ AI Valuation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  double? _listingPricePerSqft(Map<String, dynamic> item) {
    var ppsf = (item['pricePerSqft'] as num?)?.toDouble() ?? 0;
    if (ppsf <= 0) {
      final total = (item['priceRupees'] as num?)?.toDouble() ?? 0;
      final area = (item['area'] as num?)?.toDouble() ?? 0;
      if (total > 0 && area > 0) ppsf = total / area;
    }
    return ppsf > 0 ? ppsf : null;
  }

  double get _effectiveLandSizeSqft {
    if (widget.lead != null) {
      final fromExtent = parseLandExtentSqft(widget.lead!.landExtent);
      if (fromExtent != null) return fromExtent;
    }
    return double.tryParse(_landSizeCtrl.text) ?? 1000;
  }

  Widget _buildReadOnlyLandSizeSqft(double sqft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Land Size (sqft)'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.fomraSurfaceVar,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.fomraBorder.withValues(alpha: 0.85),
            ),
          ),
          child: Text(
            sqft.round().toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.fomraTextPrimary,
            ),
          ),
        ),
      ],
    );
  }

  _AreaPriceStats _areaPriceStats() {
    // Benchmark follows the selected property type — House/Plot/Flat averages
    // its own ₹/sqft; "All" uses everything. Drives the AI valuation buy price.
    final rates = _mbListings
        .where(_matchesTypeFilter)
        .map(_listingPricePerSqft)
        .whereType<double>()
        .toList()
      ..sort();
    if (rates.isEmpty) {
      return const _AreaPriceStats(
        avgPerSqft: 0,
        medianPerSqft: 0,
        pricedCount: 0,
      );
    }
    final sum = rates.fold<double>(0, (a, b) => a + b);
    final mid = rates.length ~/ 2;
    final median = rates.length.isOdd
        ? rates[mid]
        : (rates[mid - 1] + rates[mid]) / 2;
    return _AreaPriceStats(
      avgPerSqft: sum / rates.length,
      medianPerSqft: median,
      pricedCount: rates.length,
    );
  }

  _ValuationResult? _computeValuation() {
    final areaStats = _areaPriceStats();
    if (!areaStats.hasData) return null;

    // Only Land Size is asked. Buy price = area average ₹/sqft (from nearby
    // priced projects) × land size. Investment/Risk come from the auto-collected
    // infrastructure score around the pinned point.
    final benchmarkPrice = areaStats.avgPerSqft;
    final infraScore = _infraScores['Overall Location'] ?? 50;
    final landSize = _effectiveLandSizeSqft;

    final buyPerSqft = benchmarkPrice;
    final purchaseTotal = buyPerSqft * landSize;

    // Investment blends THREE signals (so it is not just the infra score):
    //   • Location quality  — infrastructure/amenities score        (50%)
    //   • Market activity   — how many priced projects are nearby   (30%)
    //   • Price headroom    — cheaper areas have more room to grow   (20%)
    final n = areaStats.pricedCount;
    final activityScore = (n * 14).clamp(0, 100).toDouble(); // ~7 projects → 100
    final rate = benchmarkPrice;
    final headroomScore = rate <= 4000
        ? 90.0
        : rate <= 8000
            ? 75.0
            : rate <= 12000
                ? 60.0
                : rate <= 18000
                    ? 45.0
                    : 30.0;
    final investmentScore =
        (infraScore * 0.5 + activityScore * 0.3 + headroomScore * 0.2)
            .round()
            .clamp(0, 100);
    final riskScore = 100 - investmentScore;

    final recommendation = investmentScore > 70
        ? 'Strong Buy'
        : investmentScore > 50
            ? 'Buy'
            : investmentScore > 35
                ? 'Hold'
                : 'Avoid';

    // Describe THIS plot's actual situation, not a generic definition.
    final locWord = infraScore >= 70
        ? 'well-developed'
        : infraScore >= 45
            ? 'moderately developed'
            : 'under-developed';
    final actWord = n >= 6
        ? 'active'
        : n >= 3
            ? 'moderate'
            : 'quiet';
    final headWord = headroomScore >= 75
        ? 'strong room to grow'
        : headroomScore >= 45
            ? 'some room to grow'
            : 'limited upside (already premium-priced)';
    final verdict = investmentScore >= 70
        ? 'a strong investment'
        : investmentScore >= 50
            ? 'a reasonable investment'
            : investmentScore >= 35
                ? 'a cautious / hold'
                : 'a weak investment';
    final investmentReason =
        'Investment $investmentScore/100 for this plot:\n'
        '• Location is $locWord — amenities (schools, hospitals, roads, transport) '
        'score ${infraScore.round()}/100.\n'
        '• Market is $actWord — $n priced project${n == 1 ? '' : 's'} nearby '
        '(${activityScore.round()}/100).\n'
        '• Pricing shows $headWord — area rate ₹${rate.round()}/sqft '
        '(${headroomScore.round()}/100).\n'
        'Overall this looks like $verdict.';

    final weaknesses = <String>[];
    if (infraScore < 55) {
      weaknesses.add('sparse infrastructure (${infraScore.round()}/100)');
    }
    if (n < 4) weaknesses.add('a $actWord market ($n nearby)');
    if (headroomScore < 55) {
      weaknesses.add('little price upside (₹${rate.round()}/sqft)');
    }
    final strengths = <String>[];
    if (infraScore >= 55) {
      strengths.add('good infrastructure (${infraScore.round()}/100)');
    }
    if (n >= 4) strengths.add('an active market ($n nearby)');
    if (headroomScore >= 55) {
      strengths.add('room to appreciate (₹${rate.round()}/sqft)');
    }
    final riskBand = riskScore >= 60
        ? 'high'
        : riskScore >= 40
            ? 'moderate'
            : 'low';
    final riskReason = 'Risk $riskScore/100 ($riskBand — it is 100 minus the '
            'investment score). '
        '${weaknesses.isNotEmpty ? 'Pushed up by ${weaknesses.join(', ')}. ' : ''}'
        '${strengths.isNotEmpty ? 'Held down by ${strengths.join(', ')}.' : ''}';

    return _ValuationResult(
      areaAvgPerSqft: benchmarkPrice,
      pricedListingCount: areaStats.pricedCount,
      landSizeSqft: landSize,
      buyPerSqft: buyPerSqft,
      sellPerSqft: buyPerSqft * 1.18,
      recommendedPurchasePrice: purchaseTotal,
      recommendedSellingPrice: purchaseTotal * 1.18,
      expectedMargin: 18,
      investmentScore: investmentScore,
      riskScore: riskScore,
      recommendation: recommendation,
      investmentReason: investmentReason,
      riskReason: riskReason,
    );
  }

  // â”€â”€ Zoom helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  double _zoomForRadius(int km) =>
      km == 2 ? 14.5 : km == 5 ? 13.0 : 12.0;

  // â”€â”€ MagicBricks Competitor Projects â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _fetchMagicBricksProjects() async {
    final city = (_detectedDistrict ?? 'Chennai')
        .replaceAll(RegExp(r'\s*[Dd]istrict\s*$'), '')
        .replaceAll(RegExp(r'\s*[Dd]t\s*$'), '')
        .trim();
    final cityParam = city.isEmpty ? 'Chennai' : city;
    final loc = _activeLatLng;
    if (loc == null) {
      setState(() {
        _mbError = 'Tap the map or enable GPS to load competitor projects in your radius.';
        _fetchingMb = false;
      });
      return;
    }

    final parts = <String>[
      'city=${Uri.encodeComponent(cityParam)}',
      'lat=${loc.latitude}',
      'lng=${loc.longitude}',
      'radius=$_compRadiusKm',
    ];
    final params = parts.join('&');
    final fetchSeq = ++_mbFetchSeq;

    setState(() {
      _fetchingMb = true;
      _mbError = null;
      _mbPartialWarning = null;
      _mbListings = [];
      _projectsExpanded = false;
      _valuationResult = null;
    });

    try {
      final result = await ApiClient.get('/api/competitors?$params')
          .timeout(const Duration(seconds: 120));

      if (!mounted || fetchSeq != _mbFetchSeq) return;

      var listings = ((result['listings'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((item) {
            final src = (item['source'] as String? ?? '').toLowerCase();
            return src.contains('nobroker') || src.contains('squareyards');
          })
          .toList();

      final radiusNote = result['radiusNote'] as String?;

      if (listings.isEmpty) {
        throw ApiException(
          statusCode: 502,
          message: radiusNote ??
              'No competitor projects in this radius. Try 10km or tap closer to a city centre.',
        );
      }

      if (!mounted || fetchSeq != _mbFetchSeq) return;

      setState(() {
        _mbListings = listings;
        _projectsExpanded = false;
        _mbSource = (result['source'] as String?) ?? 'SquareYards + NoBroker';
        final partial = result['partial'] is List
            ? (result['partial'] as List).join('; ')
            : result['partial'] as String?;
        _mbPartialWarning = [radiusNote, partial]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' · ');
        _fetchingMb = false;
      });
      _tryAutoValuation();
    } on ApiException catch (e) {
      setState(() {
        _mbError = e.message;
        _fetchingMb = false;
      });
    } on TimeoutException {
      setState(() {
        _mbError = 'Request timed out. Prices take ~1 min to load — try again.';
        _fetchingMb = false;
      });
    } catch (e) {
      setState(() {
        _mbError = 'Could not reach the server at localhost:3000. Run: cd backend && npm start';
        _fetchingMb = false;
      });
    }
  }

  // ── Competitor project classification ──────────────────────────────────────
  // Sources disagree on wording, so classify from several signals rather than a
  // single exact-match string. A project can belong to more than one bucket
  // (e.g. an old completed plot), which is why filters are evaluated per-bucket.

  static bool _isPlot(Map<String, dynamic> item) {
    final type = (item['projectType'] as String? ?? '').toLowerCase();
    if (type == 'layout' || type == 'plot') return true;
    final name = (item['projectName'] as String? ?? '').toLowerCase();
    return RegExp(r'\b(plot|plots|plotted|layout|land)\b').hasMatch(name);
  }

  // Flat (apartment) vs individual House (independent house / villa) vs Plot.
  // NoBroker supplies homeType; other sources (apartment projects) default Flat.
  static String _homeType(Map<String, dynamic> item) {
    final ht = (item['homeType'] as String? ?? '').trim();
    if (ht.isNotEmpty) return ht;
    if (_isPlot(item)) return 'Plot';
    final name = (item['projectName'] as String? ?? '').toLowerCase();
    if (RegExp(r'\b(independent house|individual house|villa)\b').hasMatch(name)) {
      return 'House';
    }
    return 'Flat';
  }

  static bool _isFlat(Map<String, dynamic> item) => _homeType(item) == 'Flat';
  static bool _isHouse(Map<String, dynamic> item) => _homeType(item) == 'House';

  // Age in years from the registration/completion year, or null if unknown.
  static int? _ageYears(Map<String, dynamic> item) {
    final y = _registeredYear(item);
    return y == null ? null : DateTime.now().year - y;
  }

  // An existing, ready-to-occupy property (resale / ready-to-move / completed).
  static bool _isReady(Map<String, dynamic> item) {
    final status = (item['status'] as String? ?? '').toLowerCase();
    final possession = (item['possession'] as String? ?? '').toLowerCase();
    return status.contains('complet') ||
        status.contains('ready') ||
        status.contains('move') ||
        status.contains('resale') ||
        status.contains('occupied') ||
        status.contains('possession given') ||
        possession.contains('ready') ||
        possession.contains('move');
  }

  // Completed = a ready property that is recently completed (under 1 year old).
  // Older ready properties fall under the "Old projects" age buckets instead.
  static bool _isCompleted(Map<String, dynamic> item) {
    if (_isPlot(item) || !_isReady(item)) return false;
    final age = _ageYears(item);
    return age == null || age < 1;
  }

  // Ongoing = under construction: a project still being built and not yet
  // ready to move in. Covers "Under Construction", "New Launch", "Nearing
  // Possession" and work-in-progress statuses — not ready/resale, not plots.
  static bool _isOngoing(Map<String, dynamic> item) {
    if (_isPlot(item) || _isReady(item)) return false;
    final status = (item['status'] as String? ?? '').toLowerCase();
    return status.contains('construct') ||
        status.contains('ongoing') ||
        status.contains('launch') ||
        status.contains('nearing') ||
        status.contains('progress') ||
        status.contains('under const');
  }

  // Registration year, derived from the RERA number's trailing year when the
  // backend didn't supply one (e.g. "TN/02/Building/011/2024" → 2024).
  static int? _registeredYear(Map<String, dynamic> item) {
    final direct = item['registeredYear'];
    if (direct is int) return direct;
    if (direct is num) return direct.toInt();
    final rera = item['reraNo'] as String? ?? '';
    final m = RegExp(r'(20\d{2})\s*$').firstMatch(rera);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  bool _matchesTypeFilter(Map<String, dynamic> item) {
    switch (_typeFilter) {
      case 'House':
        return _isHouse(item);
      case 'Plot':
        return _isPlot(item);
      case 'Flat':
        return _isFlat(item);
      default:
        return true;
    }
  }

  bool _matchesStageFilter(Map<String, dynamic> item) {
    switch (_stageFilter) {
      case 'Ongoing':
        return _isOngoing(item);
      case 'Completed':
        return _isCompleted(item);
      case 'Old':
        final age = _ageYears(item);
        if (age == null) return false;
        switch (_oldYearsFilter) {
          case 2:  return age >= 1 && age < 5;   // 1–5 years
          case 5:  return age >= 5 && age < 10;  // 5–10 years
          case 10: return age >= 10;             // 10+ years
          default: return age >= _oldYearsFilter;
        }
      default:
        return true;
    }
  }

  // Two independent layers combine (AND): property type + project stage.
  List<Map<String, dynamic>> get _filteredMbListings {
    if (_typeFilter == 'All' && _stageFilter == 'All') return _mbListings;
    return _mbListings
        .where((item) => _matchesTypeFilter(item) && _matchesStageFilter(item))
        .toList();
  }

  // Open a competitor listing on its source website (NoBroker/SquareYards…).
  Future<void> _openListingUrl(String url, String source) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return;
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!opened && mounted) {
        AppFeedback.error(context,
            'Could not open ${source.isNotEmpty ? source : 'listing'} page.');
      }
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, 'Could not open the listing page.');
      }
    }
  }

  Widget _buildMagicBricksSection() {
    // Competitor Projects are available to management users only.
    if (!AuthService.instance.isManagement) {
      return const _SectionCard(
        title: 'Competitor Projects',
        subtitle: 'Available to management only',
        icon: Icons.lock_outline_rounded,
        child: Text(
          'Competitor Projects are restricted to management users.',
        ),
      );
    }
    const mbColor = Color(0xFFE65100);
    final city = (_detectedDistrict ?? '')
        .replaceAll(RegExp(r'\s*[Dd]istrict\s*$'), '').trim();
    final areaLabel = city.isEmpty ? 'Chennai' : city;
    final radiusLabel =
        _activeLatLng != null ? ' · ${_compRadiusKm}km' : '';

    String fmtPricePerSqft(Map<String, dynamic> item) {
      var ppsf = (item['pricePerSqft'] as num?)?.toDouble() ?? 0;
      if (ppsf <= 0) {
        final total = (item['priceRupees'] as num?)?.toDouble() ?? 0;
        final area = (item['area'] as num?)?.toDouble() ?? 0;
        if (total > 0 && area > 0) ppsf = total / area;
      }
      if (ppsf <= 0) return '';
      return '₹${ppsf.toInt()}/sqft';
    }

    String fmtTotalPrice(Map<String, dynamic> item) {
      final total = (item['priceRupees'] as num?)?.toDouble() ?? 0;
      if (total >= 1e7) return '₹${(total / 1e7).toStringAsFixed(2)} Cr';
      if (total > 0) return '₹${(total / 1e5).toStringAsFixed(2)} L';
      return '';
    }

    String fmtPriceLabel(Map<String, dynamic> item) {
      final ppsf = fmtPricePerSqft(item);
      final total = fmtTotalPrice(item);
      if (ppsf.isNotEmpty && total.isNotEmpty) return '$ppsf · $total';
      if (ppsf.isNotEmpty) return ppsf;
      if (total.isNotEmpty) return total;
      return 'Price on request';
    }

    Widget chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );

    Widget metaChip(IconData icon, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: context.fomraSurfaceVar,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.fomraBorder.withValues(alpha: 0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: context.fomraTextSecondary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: context.fomraTextPrimary,
                ),
              ),
            ],
          ),
        );

    Widget typeChip(String label, bool selected, VoidCallback onSelect) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            label: Text(label, style: const TextStyle(fontSize: 11)),
            selected: selected,
            onSelected: (_) => onSelect(),
            selectedColor: mbColor.withValues(alpha: 0.14),
            checkmarkColor: mbColor,
            showCheckmark: selected,
            labelStyle: TextStyle(
              color: selected ? mbColor : context.fomraTextPrimary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            side: BorderSide(
              color: selected
                  ? mbColor.withValues(alpha: 0.45)
                  : context.fomraBorder,
            ),
            backgroundColor: context.fomraSurface,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );

    return _SectionCard(
      title: 'Competitor Projects',
      subtitle: 'Market listings in your search radius',
      icon: Icons.business_center_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            metaChip(Icons.hub_outlined, _mbSource),
            metaChip(Icons.place_outlined, '$areaLabel$radiusLabel'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Radius',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.fomraTextSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: context.fomraSurfaceVar,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.fomraBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _compRadiusKm,
                  isDense: true,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.fomraTextPrimary,
                  ),
                  items: [
                    for (var km = 1; km <= 10; km++)
                      DropdownMenuItem(
                        value: km,
                        child: Text('$km km'),
                      ),
                  ],
                  onChanged: _fetchingMb
                      ? null
                      : (km) {
                          if (km == null) return;
                          setState(() => _compRadiusKm = km);
                        },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in ['All', 'House', 'Plot', 'Flat'])
                      typeChip(
                        f,
                        _typeFilter == f,
                        () => setState(() {
                          _typeFilter = f;
                          if (_valuationResult != null) {
                            _valuationResult = _computeValuation();
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _fetchingMb ? null : _fetchMagicBricksProjects,
              icon: _fetchingMb
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.search, size: 16),
              label: Text(
                _fetchingMb ? 'Searching' : 'Search',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: mbColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                minimumSize: const Size(0, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppColors.radiusSm),
                ),
              ),
            ),
          ],
        ),

        if (_mbPartialWarning != null && _mbPartialWarning!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.isDarkMode
                  ? AppColors.warning.withValues(alpha: 0.14)
                  : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.isDarkMode
                    ? AppColors.warning.withValues(alpha: 0.4)
                    : const Color(0xFFFCD34D),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Some sources unavailable: $_mbPartialWarning',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                ),
              ),
            ]),
          ),
        ],

        if (_mbError != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_mbError!,
                    style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
              ),
            ]),
          ),
        ],

        if (_mbListings.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.fomraSurfaceVar,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: mbColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.apartment_outlined,
                    size: 18,
                    color: mbColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _typeFilter == 'All'
                            ? '${_mbListings.length} project${_mbListings.length == 1 ? '' : 's'} found'
                            : '${_filteredMbListings.length} of ${_mbListings.length} match $_typeFilter',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.fomraTextPrimary,
                        ),
                      ),
                      if (_areaPriceStats().hasData) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Avg ₹${_areaPriceStats().avgPerSqft.round()}/sqft'
                          ' · ${_areaPriceStats().pricedCount} priced'
                          ' · ${_compRadiusKm}km radius',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_projectsExpanded)
                  TextButton.icon(
                    onPressed: () => setState(() => _projectsExpanded = false),
                    icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                    label: const Text(
                      'Hide',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: context.fomraTextSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: const Size(0, 36),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => setState(() => _projectsExpanded = true),
                    icon: const Icon(Icons.list_alt_outlined, size: 16),
                    label: const Text(
                      'Show projects',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: mbColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppColors.radiusSm),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_projectsExpanded) ...[
          const SizedBox(height: 10),
          // ── Project stage (property type is chosen above, before search) ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in ['All', 'Ongoing', 'Completed', 'Old Projects'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f, style: const TextStyle(fontSize: 11)),
                    selected: _stageFilter == (f == 'Old Projects' ? 'Old' : f),
                    selectedColor: mbColor,
                    labelStyle: TextStyle(
                      color: _stageFilter == (f == 'Old Projects' ? 'Old' : f)
                          ? Colors.white
                          : context.fomraTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() {
                      _stageFilter = f == 'Old Projects' ? 'Old' : f;
                    }),
                  ),
                ),
            ]),
          ),
          if (_stageFilter == 'Old') ...[
            const SizedBox(height: 8),
            Row(children: [
              const Text('Age:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              for (final yrs in [2, 5, 10])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      yrs == 2 ? '1–5 yrs' : yrs == 5 ? '5–10 yrs' : '10+ yrs',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: _oldYearsFilter == yrs,
                    selectedColor: mbColor,
                    labelStyle: TextStyle(
                      color: _oldYearsFilter == yrs
                          ? Colors.white
                          : context.fomraTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _oldYearsFilter = yrs),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 8),
          if (_filteredMbListings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No projects match the selected filters. Try All for type and stage.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.fomraTextSecondary,
                  height: 1.4,
                ),
              ),
            )
          else ...[
          Text(
            '${_filteredMbListings.length} of ${_mbListings.length} project${_mbListings.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          ..._filteredMbListings.take(30).map((item) {
            final name      = item['projectName'] as String? ?? '';
            final locality  = item['locality']    as String? ?? '';
            final bhk       = item['bhkType']     as String? ?? '';
            final poss      = item['possession']  as String? ?? '';
            final rera      = item['reraNo']      as String? ?? '';
            final developer = item['developer']   as String? ?? '';
            final source    = item['source']      as String? ?? '';
            final detailUrl = item['detailUrl']   as String? ?? '';
            final areaSqft  = (item['area'] as num?)?.toInt() ?? 0;
            final ppsfStr   = fmtPricePerSqft(item);
            final totalStr  = fmtTotalPrice(item);
            final priceLabel = fmtPriceLabel(item);
            final hasPrice  = ppsfStr.isNotEmpty || totalStr.isNotEmpty;
            final distKm    = (item['distanceKm'] as num?)?.toDouble();
            final isTnrera  = source == 'TNRERA';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: context.fomraSurface,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: detailUrl.isEmpty
                      ? null
                      : () => _openListingUrl(detailUrl, source),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.fomraBorder),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      name.isNotEmpty ? name : locality,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.fomraTextPrimary),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasPrice && ppsfStr.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: mbColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(ppsfStr,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w800, color: mbColor)),
                        )
                      else
                        Text(priceLabel,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: hasPrice ? mbColor : AppColors.textSecondary,
                                fontStyle: hasPrice ? FontStyle.normal : FontStyle.italic)),
                      if (areaSqft > 0) ...[
                        const SizedBox(height: 4),
                        chip('$areaSqft sqft', const Color(0xFF00695C)),
                      ],
                      if (totalStr.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(totalStr,
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ]),
                if (distKm != null) ...[
                  const SizedBox(height: 4),
                  Text('${distKm.toStringAsFixed(1)} km away',
                      style: TextStyle(
                          fontSize: 10, color: context.fomraTextSecondary)),
                ],
                if (developer.isNotEmpty && isTnrera) ...[
                  const SizedBox(height: 3),
                  Text(developer,
                      style: TextStyle(
                          fontSize: 11,
                          color: context.fomraTextSecondary,
                          fontStyle: FontStyle.italic),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                if (locality.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.location_on_outlined,
                        size: 12, color: context.fomraTextSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(locality,
                          style: TextStyle(
                              fontSize: 11, color: context.fomraTextSecondary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ],
                if (bhk.isNotEmpty || (poss.isNotEmpty && poss != 'N/A') ||
                    rera.isNotEmpty || source.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (source.isNotEmpty) chip(source, const Color(0xFF6A1B9A)),
                    if (bhk.isNotEmpty) chip(bhk, const Color(0xFF1565C0)),
                    if (poss.isNotEmpty && poss != 'N/A')
                      chip(poss, AppColors.success),
                    if (rera.isNotEmpty) chip('RERA ✓', mbColor),
                  ]),
                ],
                if (detailUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.open_in_new, size: 13, color: mbColor),
                    const SizedBox(width: 4),
                    Text(
                      'View on ${source.isNotEmpty ? source : 'website'}',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: mbColor),
                    ),
                  ]),
                ],
                    ]),
                  ),
                ),
              ),
            );
          }),
          ],
          ],
        ] else if (!_fetchingMb && _mbError == null) ...[
          const SizedBox(height: 16),
          Center(
            child: Column(children: [
              Icon(Icons.business_outlined, size: 36,
                  color: mbColor.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              const Text(
                'Pick a property type and tap Search to load\nnearby competitor projects with prices.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary, height: 1.4),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  // â”€â”€ Section: EC & Patta â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildGovtDocsSection() {
    final loc = _activeLatLng;
    return _GovtDocsSection(
      district: _detectedDistrict,
      taluk: _detectedTaluk,
      village: _detectedVillage,
      surveyNumber: _tngisSurvey,
      subDivision: _tngisSubDiv,
      districtCode: _tngisDc,
      talukCode: _tngisTc,
      villageCode: _tngisVc,
      ruralUrban: _tngisRuralUrban,
      lat: loc?.latitude,
      lon: loc?.longitude,
      tngisGiViewerUrl: _tngisGiViewerUrl,
      giServices: _tngisGiServices,
      ulpin: _tngisUlpin,
      centroid: _tngisCentroid,
      tngisSubdivisions: _tngisSubdivisions,
      tngisParcelLoading: _tngisParcelLoading,
      fmbAvailable: _tngisFmbAvailable,
      fmbNote: _tngisFmbNote,
    );
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildLeadSectionOnlyBody() {
    final section = widget.leadSectionOnly!;
    final loc = _activeLatLng;

    Widget content;
    switch (section) {
      case MarketIntelLeadSection.infrastructure:
        if (loc == null && _geocodingLead) {
          content = _leadSectionLoadingCard('Locating this lead…');
        } else if (loc == null) {
          content = _leadSectionEmptyCard(
            icon: Icons.location_off_outlined,
            title: 'Location required',
            message:
                'Add GPS coordinates to this lead to load nearby infrastructure from Market Intelligence.',
          );
        } else {
          content = _buildInfrastructureSection();
        }
      case MarketIntelLeadSection.landRecords:
        content = _buildGovtDocsSection();
      case MarketIntelLeadSection.competitorProjects:
        if (loc == null && _geocodingLead) {
          content = _leadSectionLoadingCard('Locating this lead…');
        } else if (loc == null) {
          content = _leadSectionEmptyCard(
            icon: Icons.location_off_outlined,
            title: 'Location required',
            message:
                'Add GPS coordinates to this lead to load competitor projects from Market Intelligence.',
          );
        } else {
          content = _buildMagicBricksSection();
        }
    }

    if (!widget.embeddedScrollable) {
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: content,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: content,
    );
  }

  Widget _leadSectionLoadingCard(String message) {
    return _SectionCard(
      title: 'Market Intelligence',
      icon: Icons.insights_outlined,
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leadSectionEmptyCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return _SectionCard(
      title: title,
      icon: icon,
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildLeadEmbeddedBody() {
    final loc = _activeLatLng;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loc == null && _geocodingLead)
          const PortalFadeSection(
            index: 0,
            child: _SectionCard(
              title: 'Land Location',
              icon: Icons.location_on_outlined,
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Locating this lead on the map…',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (loc == null && !_geocodingLead)
          const PortalFadeSection(
            index: 0,
            child: _SectionCard(
              title: 'Location',
              icon: Icons.location_off_outlined,
              child: Text(
                'This lead has no GPS coordinates and its address could not be located. Add GPS when creating the lead to load infrastructure score and AI valuation.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
              ),
            ),
          ),
        if (loc != null) ...[
          const SizedBox(height: 20),
          PortalFadeSection(index: 1, child: _buildLeadMapSection(loc)),
          const SizedBox(height: 20),
          PortalFadeSection(index: 2, child: _buildInfrastructureSection()),
          const SizedBox(height: 20),
          PortalFadeSection(index: 3, child: _buildMagicBricksSection()),
        ],
        const SizedBox(height: 20),
        PortalFadeSection(index: 4, child: _buildGovtDocsSection()),
        const SizedBox(height: 20),
        PortalFadeSection(index: 5, child: _buildLeadValuationSection()),
      ],
    );
  }

  Widget _buildLeadMapSection(LatLng loc) {
    return _SectionCard(
      title: 'Land Location',
      subtitle: 'Pinned coordinates for this lead',
      icon: Icons.location_on_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppColors.radiusMd),
            child: SizedBox(
              height: 260,
              child: _buildMapStack(),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.fomraSurfaceVar,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${loc.latitude.toStringAsFixed(5)}° N, ${loc.longitude.toStringAsFixed(5)}° E',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: context.fomraTextSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeadValuationSection() {
    final loc = _activeLatLng;
    final stats = _areaPriceStats();
    final loading = loc != null && (_fetchingMb || _collectingPois || !_poisCollected);

    if (loading) {
      return const _SectionCard(
        title: 'AI Land Valuation Engine',
        icon: Icons.auto_awesome_outlined,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text(
                  'Computing land valuation…',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (loc == null || !stats.hasData) {
      return _SectionCard(
        title: 'AI Land Valuation Engine',
        icon: Icons.auto_awesome_outlined,
        child: Text(
          loc == null
              ? 'GPS coordinates are required to compute valuation.'
              : 'No priced competitor projects near this location.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
        ),
      );
    }

    final v = _valuationResult ?? _computeValuation();
    if (v == null) {
      return const _SectionCard(
        title: 'AI Land Valuation Engine',
        icon: Icons.auto_awesome_outlined,
        child: Text(
          'Unable to compute valuation for this lead.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }

    return _SectionCard(
      title: 'AI Land Valuation Engine',
      icon: Icons.auto_awesome_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReadOnlyLandSizeSqft(_effectiveLandSizeSqft),
          if ((widget.lead?.landExtent.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 6),
            Builder(builder: (_) {
              final ext = widget.lead!.landExtent.trim();
              final extSqft = parseLandExtentSqft(ext);
              return Text(
                'Land extent: $ext'
                '${extSqft != null ? ' ≈ ${extSqft.round()} sqft' : ''}',
                style: TextStyle(
                    fontSize: 11, color: context.fomraTextSecondary),
              );
            }),
          ],
          const SizedBox(height: 16),
          _simpleValuationOutput(v),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embeddedInLead) {
      if (widget.leadSectionOnly != null) {
        return _buildLeadSectionOnlyBody();
      }
      return _buildLeadEmbeddedBody();
    }

    final body = portalScrollBody(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            PortalFadeSection(index: 0, child: _buildSearchSection()),
            const SizedBox(height: 24),
            PortalFadeSection(index: 1, child: _buildMapSection()),
            const SizedBox(height: 24),
            PortalFadeSection(index: 2, child: _buildGovtDocsSection()),
            const SizedBox(height: 24),
            PortalFadeSection(index: 3, child: _buildInfrastructureSection()),
            const SizedBox(height: 24),
            PortalFadeSection(index: 4, child: _buildMagicBricksSection()),
            const SizedBox(height: 24),
            PortalFadeSection(index: 5, child: _buildValuationSection()),
            const SizedBox(height: 32),
          ],
        ),
    );
    return FomraAppShell(
      currentRoute: '/market-intelligence',
      backgroundColor: context.fomraSurfaceVar,
      appBar: const FomraAppBar(moduleName: 'Market Intelligence'),
      body: _wrapWithFullScreenMap(body),
    );
  }

  Widget _wrapWithFullScreenMap(Widget body) {
    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        if (_mapFullScreen) Positioned.fill(child: _buildFullScreenMapOverlay()),
      ],
    );
  }


  // â”€â”€ EC & Patta: reverse-geocode district/taluk/village â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _fetchLocationDetails(LatLng loc) async {
    try {
      final res = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${loc.latitude}&lon=${loc.longitude}'),
        headers: {
          'User-Agent': 'FomraLS/1.0 (in.fomrahousing)',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final addr =
            (jsonDecode(res.body)['address'] as Map<String, dynamic>?) ?? {};
        setState(() {
          _detectedDistrict = (addr['county'] as String? ??
                  addr['state_district'] as String? ??
                  addr['city'] as String?)
              ?.replaceAll(RegExp(r'\s+[Dd]istrict$'), '')
              .trim();
          _detectedTaluk = addr['suburb'] as String? ??
              addr['city_district'] as String? ??
              addr['municipality'] as String? ??
              addr['town'] as String?;
          _detectedVillage = addr['village'] as String? ??
              addr['hamlet'] as String? ??
              addr['neighbourhood'] as String?;
        });
      }
    } catch (_) {}
  }

  // â”€â”€ Section: Search Location Setup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildSearchSection() {
    return _SectionCard(
      title: 'Search Location Setup',
      subtitle: 'Find and pin your analysis area',
      icon: Icons.search_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 560;
              final searchField = TextField(
                controller: _searchCtrl,
                decoration: _inputDec(context, 'Search city, area, landmark…')
                    .copyWith(
                  filled: true,
                  fillColor: context.fomraSurface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: context.fomraBorder.withValues(alpha: 0.8),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: context.fomraBorder.withValues(alpha: 0.8),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: _searchLocation,
              );
              final searchButton = SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _searchingLocation
                      ? null
                      : () => _searchLocation(_searchCtrl.text),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _searchingLocation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.travel_explore_outlined, size: 18),
                  label: Text(
                    _searchingLocation ? 'Searching…' : 'Search',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 12),
                    searchButton,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  searchButton,
                ],
              );
            },
          ),
          if (_searchError != null) ...[
            const SizedBox(height: 6),
            _ErrorBanner(_searchError!),
          ],
          if (_showSearchResults && _searchResults.isNotEmpty) ...[
            const SizedBox(height: 6),
            NotificationListener<ScrollNotification>(
              // Keep wheel/drag scrolling inside the suggestions list — don't
              // let it bubble to the map or page behind it.
              onNotification: (_) => true,
              child: Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: context.fomraSurface,
                borderRadius: BorderRadius.circular(AppColors.radiusSm),
                border: Border.all(color: context.fomraBorder),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 40),
                itemBuilder: (_, i) {
                  final r = _searchResults[i];
                  final name = r['display_name'] as String? ?? '';
                  return InkWell(
                    onTap: () => _selectSearchResult(r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.fomraTextPrimary)),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onTap) =>
      MarketIntelGlassButton(
        icon: icon,
        onTap: _mapReady ? onTap : null,
        primary: true,
      );

  Widget _buildMapOverlayButton(IconData icon, VoidCallback onTap) =>
      MarketIntelGlassButton(
        icon: icon,
        onTap: onTap,
        iconColor: AppColors.primary,
      );

  void _setMapLayer(_MarketMapLayer layer) {
    setState(() => _mapLayer = layer);
  }

  Widget _buildMapLayerChip(_MarketMapLayer layer, String label, IconData icon) {
    final selected = _mapLayer == layer;
    final isDark = context.isDarkMode;
    // Solid, high-contrast pills that clearly follow the theme:
    //  selected  -> accent fill with white text (both modes)
    //  unselected-> dark slate (dark mode) / white (light mode)
    const darkSurface = Color(0xFF1E293B);
    final selectedBg = isDark ? AppColors.primaryLight : AppColors.primary;
    final unselectedBg = (isDark ? darkSurface : Colors.white).withValues(alpha: 0.94);
    const selectedFg = Colors.white;
    final unselectedFg = isDark ? Colors.white.withValues(alpha: 0.9) : AppColors.primary;
    final borderColor = selected
        ? Colors.transparent
        : (isDark
            ? Colors.white.withValues(alpha: 0.18)
            : context.fomraBorder.withValues(alpha: 0.85));

    return Material(
      color: selected ? selectedBg : unselectedBg,
      elevation: selected ? 2 : 1,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _setMapLayer(layer),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14, color: selected ? selectedFg : unselectedFg),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? selectedFg : unselectedFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapStack({bool showMaximize = false, bool showMinimize = false}) {
    final activeLoc = _activeLatLng;
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: activeLoc ?? _kDefaultCenter,
              initialZoom: _zoomForRadius(_selectedRadius),
              onMapReady: () => setState(() => _mapReady = true),
              onTap: (_, point) => _handleMapTap(point),
            ),
            children: [
              MapTilerTiles.tileLayer(
                urlTemplate: MapTilerTiles.urlFor(
                  satelliteLayer: _mapLayer == _MarketMapLayer.satellite,
                ),
                satelliteLayer: _mapLayer == _MarketMapLayer.satellite,
              ),
              CircleLayer(circles: [
                if (activeLoc != null)
                  CircleMarker(
                    point: activeLoc,
                    radius: _selectedRadius * 1000.0,
                    useRadiusInMeter: true,
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderColor: AppColors.primary,
                    borderStrokeWidth: 2,
                  ),
              ]),
              MarkerLayer(markers: [
                if (activeLoc != null)
                  Marker(
                    point: activeLoc,
                    width: 40,
                    height: 48,
                    child: Icon(Icons.location_on,
                        color: _searchMode
                            ? const Color(0xFF1565C0)
                            : const Color(0xFFE53935),
                        size: 40),
                  ),
                if (_tappedPoint != null)
                  Marker(
                    point: _tappedPoint!,
                    width: 36,
                    height: 44,
                    child: const Icon(Icons.location_searching,
                        color: Color(0xFF6A1B9A), size: 32),
                  ),
              ]),
            ],
          ),
        ),
        if (_fetchingLocation || _searchingLocation)
          Container(
            color: Colors.black26,
            child: const Center(
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            ),
          ),
        if (activeLoc == null && !_fetchingLocation && !_searchingLocation)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Tap to set location',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        Positioned(
          top: 8,
          left: 8,
          child: Row(
            children: [
              _buildMapLayerChip(
                _MarketMapLayer.standard,
                'Standard',
                Icons.map_outlined,
              ),
              const SizedBox(width: 6),
              _buildMapLayerChip(
                _MarketMapLayer.satellite,
                'Satellite',
                Icons.satellite_alt_outlined,
              ),
            ],
          ),
        ),
        if (showMaximize)
          Positioned(
            top: 8,
            right: 8,
            child: _buildMapOverlayButton(
              Icons.fullscreen,
              () => setState(() => _mapFullScreen = true),
            ),
          ),
        if (showMinimize)
          Positioned(
            top: 8,
            right: 8,
            child: _buildMapOverlayButton(
              Icons.fullscreen_exit,
              () => setState(() => _mapFullScreen = false),
            ),
          ),
        Positioned(
          right: 8,
          bottom: 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildZoomButton(Icons.add, () {
                if (_mapReady) {
                  _mapController.move(
                    _mapController.camera.center,
                    (_mapController.camera.zoom + 1).clamp(3.0, 18.0),
                  );
                }
              }),
              const SizedBox(height: 6),
              _buildZoomButton(Icons.remove, () {
                if (_mapReady) {
                  _mapController.move(
                    _mapController.camera.center,
                    (_mapController.camera.zoom - 1).clamp(3.0, 18.0),
                  );
                }
              }),
            ],
          ),
        ),
        Positioned(
          right: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              MapTilerTiles.attribution,
              style: TextStyle(fontSize: 9, color: Colors.black87),
            ),
          ),
        ),
        if (!MapTilerTiles.isConfigured)
          Positioned.fill(
            child: Container(
              color: Colors.black38,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: const Text(
                'Add your MapTiler API key at build time:\n'
                '--dart-define=MAPTILER_API_KEY=your_key',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMapFullscreenPlaceholder() {
    return Container(
      color: const Color(0xFFE8EAF6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.map_outlined, size: 36, color: AppColors.primary),
          const SizedBox(height: 8),
          const Text(
            'Map expanded to full screen',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _mapFullScreen = false),
            icon: const Icon(Icons.fullscreen_exit, size: 18),
            label: const Text('Exit full screen'),
          ),
        ],
      ),
    );
  }

  Widget _buildFullScreenMapOverlay() {
    final activeLoc = _activeLatLng;
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildMapStack(showMinimize: true),
            ),
            if (activeLoc != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(AppColors.radiusSm),
                  ),
                  child: Text(
                    '${activeLoc.latitude.toStringAsFixed(5)}° N, '
                    '${activeLoc.longitude.toStringAsFixed(5)}° E · '
                    'Tap plot for TNGIS survey',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Section: Map Visualization â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildMapSection() {
    final activeLoc = _activeLatLng;
    return _SectionCard(
      title: 'Map Visualization',
      subtitle: 'Explore parcel location and map layers',
      icon: Icons.map_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SizedBox(
                height: 320,
                child: _mapFullScreen
                    ? _buildMapFullscreenPlaceholder()
                    : _buildMapStack(showMaximize: true),
              ),
            ),
          ),
          const SizedBox(height: 10),

          if (activeLoc != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.fomraSurfaceVar,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Pinned: ${activeLoc.latitude.toStringAsFixed(5)}° N, ${activeLoc.longitude.toStringAsFixed(5)}° E',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap directly on the land plot — survey & subdivision are read from TNGIS.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            if (_tngisParcelLoading) ...[
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Reading parcel from TNGIS…',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ],
            if (_tngisParcelError != null && !_tngisParcelLoading) ...[
              const SizedBox(height: 6),
              Text(_tngisParcelError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
            ],
            const SizedBox(height: 10),
          ],
          if (_locationError != null) ...[
            _ErrorBanner(_locationError!),
            const SizedBox(height: 10),
          ],
      ]),
    );
  }

  // â”€â”€ Section: POI Collection â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showPoiList(_PoiCategory cat) {
    final places = _poiPlaces[cat.name] ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PoiListSheet(category: cat, places: places),
    );
  }

  Widget _buildInfrastructureSection() {
    final scores = _infraScores;
    final overall = scores['Overall Location'] ?? 0;
    final overallColor = overall > 70
        ? AppColors.success
        : overall > 45
            ? AppColors.warning
            : AppColors.error;

    final barData = _kInfraCategoryOrder
        .where((k) => scores.containsKey(k))
        .map((k) => MapEntry(k, scores[k]!))
        .toList();

    return _SectionCard(
      title: 'Infrastructure Score',
      subtitle: 'Nearby infrastructure analytics',
      icon: Icons.analytics_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text(
              'Radius:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            ...([2, 5, 10]).map((km) {
              final selected = _selectedRadius == km;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: MarketIntelFilterChip(
                  label: '${km}km',
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _selectedRadius = km;
                      _poisCollected = false;
                      _poiCounts = {};
                      _poiPlaces = {};
                      _infraScoreMap = {};
                      _valuationResult = null;
                      if (_activeLatLng != null && _mapReady && !widget.embeddedInLead) {
                        _mapController.move(
                            _activeLatLng!, _zoomForRadius(km));
                      }
                    });
                    if (_activeLatLng != null) _fetchMagicBricksProjects();
                    if (_activeLatLng != null) _collectPois();
                  },
                ),
              );
            }),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_activeLatLng == null || _collectingPois)
                  ? null
                  : _collectPois,
              icon: _collectingPois
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.radar, size: 18),
              label: Text(_collectingPois
                  ? 'Loading from OpenStreetMap…'
                  : 'Refresh Infrastructure Score'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          if (_activeLatLng == null && !_collectingPois) ...[
            const SizedBox(height: 10),
            Text(
              widget.embeddedInLead
                  ? 'GPS coordinates are required to score infrastructure.'
                  : 'Set your location on the map to score nearby infrastructure via OpenStreetMap.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          if (_collectingPois && !_poisCollected) ...[
            const SizedBox(height: 16),
              Center(
                child: Column(
                children: [
                  const SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(strokeWidth: 2.8),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Fetching from OpenStreetMap via Overpass…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Usually 5–15 seconds for the first load.',
                    style: TextStyle(
                        fontSize: 10, color: context.fomraTextSecondary),
                  ),
                ],
              ),
            ),
          ],
          if (_collectingPois && _poisCollected) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Refreshing infrastructure scores…',
                  style: TextStyle(
                      fontSize: 11, color: context.fomraTextSecondary),
                ),
              ],
            ),
          ],
          if (_poiError != null) ...[
            const SizedBox(height: 10),
            _ErrorBanner(_poiError!),
          ],
          if (_poisCollected) ...[
            const SizedBox(height: 12),
            Text(
              'Weighted: Education 25% · Healthcare 20% · Roads 25% · Commercial 15% · Transport 15%. Nearest-amenity + count scoring.',
              style: TextStyle(
                  fontSize: 10, color: context.fomraTextSecondary, height: 1.35),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.fomraSurfaceVar,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: overallColor.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                SizedBox(
                  width: 94,
                  height: 94,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 94,
                        height: 94,
                        child: CircularProgressIndicator(
                          value: (overall / 100).clamp(0, 1),
                          strokeWidth: 8,
                          backgroundColor: overallColor.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(overallColor),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${overall.toInt()}',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: overallColor),
                          ),
                          Text('/100',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: context.fomraTextSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overall Location Score',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: overallColor),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        overall > 70
                            ? 'Excellent infrastructure in this area.'
                            : overall > 45
                                ? 'Moderate infrastructure. Room to grow.'
                                : 'Infrastructure needs development.',
                        style: TextStyle(
                            fontSize: 12,
                            color: context.fomraTextSecondary,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: barData.map((e) {
                final score = e.value;
                final color = score > 70
                    ? AppColors.success
                    : score > 45
                        ? AppColors.warning
                        : AppColors.error;
                return Container(
                  width: 148,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.fomraTextPrimary)),
                      const SizedBox(height: 4),
                      Text('${score.toInt()}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: color)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: (score / 100).clamp(0, 1),
                          minHeight: 5,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.2),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Builder(builder: (context) {
              final chartGridLine = context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE5E7EB);
              final chartAxisLabel = context.fomraTextSecondary;
              final barTrackColor = context.isDarkMode
                  ? context.fomraBorder.withValues(alpha: 0.28)
                  : null;

              return SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: 100,
                  barGroups: barData.asMap().entries.map((e) {
                    final score = e.value.value;
                    final barColor = score > 70
                        ? AppColors.success
                        : score > 45
                            ? AppColors.warning
                            : AppColors.error;
                    return BarChartGroupData(x: e.key, barRods: [
                      BarChartRodData(
                        toY: score,
                        color: barColor,
                        width: 22,
                        borderRadius: BorderRadius.circular(4),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: 100,
                          color: barTrackColor ??
                              barColor.withValues(alpha: 0.08),
                        ),
                      ),
                    ]);
                  }).toList(),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}',
                          style: TextStyle(
                              fontSize: 10, color: chartAxisLabel),
                        ),
                        interval: 25,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= barData.length) {
                            return const SizedBox.shrink();
                          }
                          final label =
                              barData[idx].key.replaceAll(' ', '\n');
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 8, color: chartAxisLabel),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (_) => FlLine(
                        color: chartGridLine, strokeWidth: 1),
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            );
            }),
            const SizedBox(height: 12),
            ...barData.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ScoreRow(
                  label: e.key,
                  score: e.value,
                ),
              ),
            ),
            if (_poiCounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Nearby amenities (tap for Google Maps)',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.fomraTextSecondary),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _kCategories.map((cat) {
                  final count = _poiCounts[cat.name] ?? 0;
                  return Material(
                    color: cat.color.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () => _showPoiList(cat),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: cat.color.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(cat.icon, color: cat.color, size: 13),
                          const SizedBox(width: 5),
                          Text(
                            '$count',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: cat.color),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cat.name,
                            style: TextStyle(
                                fontSize: 10,
                                color: context.fomraTextSecondary),
                          ),
                          const SizedBox(width: 3),
                          Icon(Icons.chevron_right,
                              size: 12,
                              color: cat.color.withValues(alpha: 0.6)),
                        ]),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }


  // â”€â”€ Section: AI Valuation Engine â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildValuationSection() => _SectionCard(
        title: 'AI Land Valuation Engine',
        subtitle: 'Estimate value from nearby market data',
        icon: Icons.auto_awesome_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _FieldLabel('Land Size (sqft)'),
          TextField(
            controller: _landSizeCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDec(context, 'e.g. 5000'),
            onChanged: (_) {
              if (_valuationResult != null) {
                setState(() => _valuationResult = _computeValuation());
              }
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _areaPriceStats().hasData && !_fetchingMb
                  ? () => setState(
                        () => _valuationResult = _computeValuation(),
                      )
                  : null,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Generate Valuation'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (!_areaPriceStats().hasData &&
              _activeLatLng != null &&
              !_fetchingMb) ...[
            const SizedBox(height: 8),
            Text(
              'Valuation needs priced competitor projects near the pinned point.',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
            ),
          ],
          if (_valuationResult != null) ...[
            const SizedBox(height: 20),
            _simpleValuationOutput(_valuationResult!),
          ],
        ]),
      );

  // The only outputs: expected buy price, investment score, risk score.
  Widget _simpleValuationOutput(_ValuationResult v) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: _LeadValuationAmountTile(
          label: 'Expected Buying Price',
          amount: _fmtIndianRupee(v.recommendedPurchasePrice),
          color: AppColors.info,
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _showScoreExplanation(
                'Investment Score', '${v.investmentScore}/100',
                v.investmentReason, AppColors.success),
            child: _BenchmarkTile('Investment ⓘ', '${v.investmentScore}/100',
                AppColors.success),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => _showScoreExplanation(
                'Risk Score', '${v.riskScore}/100', v.riskReason,
                AppColors.warning),
            child: _BenchmarkTile(
                'Risk ⓘ', '${v.riskScore}/100', AppColors.warning),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Text('Tap Investment or Risk to see why.',
          style: TextStyle(fontSize: 10, color: context.fomraTextSecondary)),
    ]);
  }

  void _showScoreExplanation(
      String title, String value, String reason, Color color) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.info_outline, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ]),
        content: Text(
          reason.isNotEmpty ? reason : 'No details available for this score.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Got it')),
        ],
      ),
    );
  }

  // â”€â”€ Section: Competitor Intelligence â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

}

// â”€â”€ Location Details Sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€



// ── POI List Sheet ───────────────────────────────────────────────────────────

Future<void> _openPlaceOnGoogleMaps(
  BuildContext context, {
  required String placeName,
  double? lat,
  double? lon,
}) async {
  final Uri uri;
  if (lat != null && lon != null) {
    uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$placeName@$lat,$lon',
    });
  } else {
    uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': placeName,
    });
  }
  try {
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!opened && context.mounted) {
      AppFeedback.error(context, 'Could not open Google Maps');
    }
  } catch (_) {
    if (context.mounted) {
      AppFeedback.error(context, 'Could not open Google Maps');
    }
  }
}

class _PoiListSheet extends StatelessWidget {
  final _PoiCategory category;
  final List<Map<String, dynamic>> places;
  const _PoiListSheet({required this.category, required this.places});

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: context.fomraSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            _Handle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(category.icon, color: category.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.name,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: context.fomraTextPrimary)),
                        Text('${places.length} found nearby',
                            style: TextStyle(
                                fontSize: 12,
                                color: context.fomraTextSecondary)),
                      ]),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close,
                      size: 20, color: context.fomraTextSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),
            Divider(height: 1, color: context.fomraBorder),
            Expanded(
              child: places.isEmpty
                  ? Center(
                      child: Text('No places found in this category.',
                          style:
                              TextStyle(color: context.fomraTextSecondary)))
                  : ListView.separated(
                      controller: ctrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: places.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: 52, color: context.fomraBorder),
                      itemBuilder: (_, i) {
                        final p = places[i];
                        final dist = p['distance'] as double?;
                        final name = p['name'] as String;
                        final lat = (p['lat'] as num?)?.toDouble();
                        final lon = (p['lon'] as num?)?.toDouble();
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _openPlaceOnGoogleMaps(
                              context,
                              placeName: name,
                              lat: lat,
                              lon: lon,
                            ),
                            borderRadius: BorderRadius.circular(AppColors.radiusSm),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Row(children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: category.color
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(category.icon,
                                      color: category.color, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(name,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: context.fomraTextPrimary)),
                                ),
                                if (dist != null) ...[
                                  const SizedBox(width: 8),
                                  Text('${dist.toStringAsFixed(1)} km',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: context.fomraTextSecondary)),
                                ],
                                const SizedBox(width: 6),
                                Icon(Icons.map_outlined,
                                    size: 14,
                                    color: category.color
                                        .withValues(alpha: 0.7)),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ]),
        ),
      );
}

// â”€â”€ Small Widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => MarketIntelSectionCard(
        title: title,
        subtitle: subtitle,
        icon: icon,
        child: child,
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 14, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.error))),
        ]),
      );
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final double score;
  const _ScoreRow({required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score > 70
        ? AppColors.success
        : score > 45
            ? AppColors.warning
            : AppColors.error;
    final isWide = MediaQuery.of(context).size.width > 600;
    return Row(children: [
      Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: isWide ? 15 : 12, color: AppColors.textSecondary))),
      SizedBox(
        width: isWide ? 200 : 120,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: context.fomraSurfaceVar,
            color: color,
            minHeight: isWide ? 10 : 6,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('${score.toInt()}',
          style: TextStyle(
              fontSize: isWide ? 15 : 12, color: color, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _LeadValuationAmountTile extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;

  const _LeadValuationAmountTile({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              amount,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      );
}

class _BenchmarkTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _BenchmarkTile(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w800,
                    height: 1.1)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9,
                    color: color.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                    height: 1.2)),
          ],
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.fomraTextSecondary,
          ),
        ),
      );
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.fomraBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
}

InputDecoration _inputDec(BuildContext context, String? hint) =>
    FomraInput.decoration(context: context, hint: hint);

class _Option {
  final String code;
  final String name;
  const _Option(this.code, this.name);
  @override
  bool operator ==(Object other) => other is _Option && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

class _EcPeriod {
  final String id;
  final String label;
  final String fromDate;
  final String toDate;
  const _EcPeriod(this.id, this.label, this.fromDate, this.toDate);

  factory _EcPeriod.fromJson(Map<String, dynamic> j) => _EcPeriod(
        j['id'] as String,
        j['label'] as String,
        j['fromDate'] as String,
        j['toDate'] as String,
      );
}

class _EcEntry {
  final String id;
  final String label;
  const _EcEntry(this.id, this.label);
}

class _TngisSubdivisionRow {
  final String surveyNumber;
  final String? subDivision;
  final String? kide;
  final Map<String, String> fields;
  final bool containsPoint;
  final bool fmbAvailable;

  const _TngisSubdivisionRow({
    required this.surveyNumber,
    this.subDivision,
    this.kide,
    this.fields = const {},
    this.containsPoint = false,
    this.fmbAvailable = false,
  });

  factory _TngisSubdivisionRow.fromJson(Map<String, dynamic> j) {
    final fields = (j['fields'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    final kideRaw = j['kide']?.toString() ?? fields['Kide'];
    final survey =
        j['surveyNumber']?.toString() ?? fields['Survey Number'] ?? '';
    final sub = _parseTngisSubDivision(
      j['subDivision']?.toString() ?? fields['Sub Division'],
      kideRaw,
      survey,
    );
    return _TngisSubdivisionRow(
      surveyNumber: survey,
      subDivision: sub,
      kide: (kideRaw != null && kideRaw.trim().isNotEmpty) ? kideRaw.trim() : null,
      fields: fields,
      containsPoint: j['containsPoint'] == true,
      fmbAvailable: j['fmbAvailable'] == true,
    );
  }

  String get key => '$surveyNumber|${subDivision ?? kide ?? ''}';

  /// Sub-division for FMB/EC — from sub_division or kide (e.g. 394/15C → 15C).
  String? get effectiveSubDivision =>
      _parseTngisSubDivision(subDivision, kide, surveyNumber);

  String get subLabel {
    return effectiveSubDivision ?? '—';
  }

  static String? _parseTngisSubDivision(String? subDiv, String? kide, String survey) {
    final s = subDiv?.trim();
    if (s != null && s.isNotEmpty && s != '-' && s != survey) return s;
    final k = kide?.trim();
    if (k == null || k.isEmpty || k == '0' || !k.contains('/')) return null;
    final parts = k.split('/');
    if (parts.length < 2) return null;
    final kideSub = parts.sublist(1).join('/').trim();
    if (kideSub.isEmpty || kideSub == '-' || kideSub == survey) return null;
    final kideSurvey = parts[0].trim();
    if (kideSurvey.isNotEmpty && kideSurvey != survey) return null;
    return kideSub;
  }

  /// Keep only the subdivision row for the map tap / resolved sub.
  static List<_TngisSubdivisionRow> filterForTap(
    List<_TngisSubdivisionRow> rows,
    String? resolvedSub,
    String? survey,
  ) {
    if (rows.isEmpty) return rows;
    final surveyTrim = survey?.trim();

    final atPoint = rows.where((r) => r.containsPoint).toList();
    if (atPoint.length == 1) return atPoint;
    if (atPoint.length > 1) return [atPoint.first];

    final sub = resolvedSub?.trim();
    if (sub != null &&
        sub.isNotEmpty &&
        sub != '-' &&
        sub != surveyTrim) {
      final norm = sub.toUpperCase();
      for (final r in rows) {
        if (r.effectiveSubDivision?.trim().toUpperCase() == norm) return [r];
      }
    }

    // Parent survey (no sub-division on record)
    for (final r in rows) {
      if (r.effectiveSubDivision == null) return [r];
    }

    if (rows.length == 1) return rows;
    return [rows.first];
  }
}

class _SubdivDocBundle {
  Map<String, dynamic>? documents;
  Uint8List? fmbPdf;
  bool loadingPatta = false;
  bool loadingFmb = false;
  String? fmbError;
}

// â”€â”€ EC & Patta: main section widget â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _GovtDocsSection extends StatefulWidget {
  final String? district;
  final String? taluk;
  final String? village;
  final String? surveyNumber;
  final String? subDivision;
  final String? districtCode;
  final String? talukCode;
  final String? villageCode;
  final String? ruralUrban; // 'rural' (FMB) | 'urban' (TSLR) — drives labels
  final double? lat; // active map location — enables the TNGIS patta fallback
  final double? lon;
  final String? tngisGiViewerUrl;
  final Map<String, dynamic>? giServices;
  final String? ulpin;
  final String? centroid;
  final List<_TngisSubdivisionRow> tngisSubdivisions;
  final bool tngisParcelLoading;
  final bool fmbAvailable;
  final String? fmbNote;
  const _GovtDocsSection({
    this.district,
    this.taluk,
    this.village,
    this.surveyNumber,
    this.subDivision,
    this.districtCode,
    this.talukCode,
    this.villageCode,
    this.ruralUrban,
    this.lat,
    this.lon,
    this.tngisGiViewerUrl,
    this.giServices,
    this.ulpin,
    this.centroid,
    this.tngisSubdivisions = const [],
    this.tngisParcelLoading = false,
    this.fmbAvailable = false,
    this.fmbNote,
  });

  @override
  State<_GovtDocsSection> createState() => _GovtDocsSectionState();
}

class _GovtDocsSectionState extends State<_GovtDocsSection> {
  // Urban land uses the TSLR system (Town Survey No. + block) rather than the
  // rural FMB survey-number/sub-division, so relabel the fields accordingly.
  bool get _isUrban {
    final ru = (widget.ruralUrban ?? '').toLowerCase();
    return ru.contains('urban') || ru == 'u';
  }
  String get _surveyLabel => _isUrban ? 'T.S. Number' : 'Survey Number';
  String get _subLabel => _isUrban ? 'Block / Sub-div' : 'Sub Division';

  // ── Patta state ──
  List<_Option> _districts = _kStaticDistricts;
  _Option? _selDistrict;
  List<_Option> _taluks   = [];
  _Option? _selTaluk;
  _Option? _selVillage;
  final _surveyCtrl  = TextEditingController();
  final _subDivCtrl  = TextEditingController();
  bool   _fetchingPatta   = false;
  Map<String, String>?      _pattaFields;
  String? _pattaError;
  Map<String, dynamic>? _pattaDocuments;
  final Map<String, _SubdivDocBundle> _subdivBundles = {};
  Uint8List? _fmbPdfBytes;
  String? _fmbLoadError;
  bool _loadingFmb = false;
  Timer? _pattaDebounce;

  // â”€â”€ EC state â”€â”€

  // Keyed by district code. SRO codes are sequential placeholders;
  // real codes are loaded from tnreginet when reachable.
  _Option? _selZone;
  _Option? _selEcDist;
  List<_Option> _ecSros  = [];
  _Option? _selEcSro;
  final _ecSurveyCtrl = TextEditingController();
  final _ecSubDivCtrl = TextEditingController();
  final _ecFromCtrl   = TextEditingController();
  final _ecToCtrl     = TextEditingController();
  bool   _fetchingEc   = false;
  List<Map<String, String>> _ecAllRecords = [];
  String? _selEcEntryId;
  String? _ecDocumentHtml;
  Uint8List? _ecPdfBytes;
  String? _ecPdfFileName;
  String? _ecSource;
  Map<String, String> _ecMeta = {};
  List<_EcPeriod> _ecPeriods = [];
  _EcPeriod? _selEcPeriod;
  String? _ecError;
  String? _ecCaptchaSession;
  final _ecCaptchaCtrl = TextEditingController();

  String? _selectedGiService;
  bool _loadingGvalue = false;
  bool _loadingCrop = false;
  Map<String, dynamic>? _gvalueData;
  Map<String, dynamic>? _cropData;
  String? _gvalueError;
  String? _cropError;
  String? _selectedCropSeason;

  static const _kGiServices = [
    (id: 'patta', label: 'Patta', icon: Icons.article_outlined, color: Color(0xFF1B5E20)),
    (id: 'fmb', label: 'FMB', icon: Icons.picture_as_pdf_outlined, color: Color(0xFFC62828)),
    (id: 'ec', label: 'EC', icon: Icons.account_balance_outlined, color: Color(0xFF1565C0)),
    (id: 'gvalue', label: 'G-Value', icon: Icons.currency_rupee_outlined, color: Color(0xFFE65100)),
    (id: 'crop', label: 'Crop', icon: Icons.grass_outlined, color: Color(0xFF2E7D32)),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _ecFromCtrl.text = '01/01/2000';
    _ecToCtrl.text =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    _applySurveyNumber();
    _initDistricts();
    _loadEcPeriods();
    _loadEcZones();
    _loadEcCaptcha();
    if (widget.district != null) {
      _tryAutoEcFill();
    } else if (widget.lat != null && widget.lon != null) {
      Future.microtask(() => _resolveEcFromServer());
    }
    _surveyCtrl.addListener(_onSurveyChanged);
    _ecSurveyCtrl.addListener(_onEcSurveyChanged);
  }

  void _onSurveyChanged() {
    _pattaDebounce?.cancel();
    if (_surveyCtrl.text.trim().isEmpty) return;
    _pattaDebounce = Timer(const Duration(milliseconds: 900), _fetchPattaBySurveyNo);
  }

  void _onEcSurveyChanged() {
    _pattaDebounce?.cancel();
    _pattaDebounce = Timer(const Duration(milliseconds: 900), _maybeAutoFetchEc);
  }

  /// Mirrors a lead's survey number / sub-division into the Patta + EC inputs.
  void _applySurveyNumber() {
    final s = widget.surveyNumber?.trim() ?? '';
    if (s.isNotEmpty) {
      if (_surveyCtrl.text != s) _surveyCtrl.text = s;
      if (_ecSurveyCtrl.text != s) _ecSurveyCtrl.text = s;
    }
    final sd = widget.subDivision?.trim() ?? '';
    if (sd.isNotEmpty) {
      if (_subDivCtrl.text != sd) _subDivCtrl.text = sd;
      if (_ecSubDivCtrl.text != sd) _ecSubDivCtrl.text = sd;
    }
  }

  /// Auto-fetches Patta once district/taluk/village are resolved AND a survey
  /// number is available (lead-based mode). No-op otherwise.
  void _maybeAutoFetchPatta() {
    final s = widget.surveyNumber?.trim() ?? '';
    if (s.isEmpty || _fetchingPatta) return;
    if (_selDistrict == null || _selTaluk == null || _selVillage == null) return;
    _surveyCtrl.text = s;
    _fetchPatta();
  }

  /// Auto-fetches EC once zone/district/SRO are resolved AND a survey number is
  /// available (typed or from lead).
  void _maybeAutoFetchEc() {
    final s = _ecSurveyCtrl.text.trim().isNotEmpty
        ? _ecSurveyCtrl.text.trim()
        : (widget.surveyNumber?.trim() ?? '');
    if (s.isEmpty || _fetchingEc) return;
    if (_selZone == null || _selEcDist == null || _selEcSro == null) return;
    if (_ecSurveyCtrl.text != s) _ecSurveyCtrl.text = s;
    _searchEc();
  }

  @override
  void didUpdateWidget(covariant _GovtDocsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Location is resolved asynchronously (GPS + reverse geocode), so the
    // district/taluk/village usually arrive AFTER the first build. Re-run the
    // auto-fill whenever they change so EC & Patta populate with the location.
    final locationChanged = oldWidget.district != widget.district ||
        oldWidget.taluk != widget.taluk ||
        oldWidget.village != widget.village;
    final surveyChanged = oldWidget.surveyNumber != widget.surveyNumber ||
        oldWidget.subDivision != widget.subDivision;
    final codesChanged = oldWidget.districtCode != widget.districtCode ||
        oldWidget.talukCode != widget.talukCode ||
        oldWidget.villageCode != widget.villageCode;

    if (surveyChanged) _applySurveyNumber();

    final coordsChanged = oldWidget.lat != widget.lat || oldWidget.lon != widget.lon;
    if (coordsChanged) {
      _fmbPdfBytes = null;
      _fmbLoadError = null;
      _loadingFmb = false;
      for (final b in _subdivBundles.values) {
        b.fmbPdf = null;
        b.fmbError = null;
        b.loadingFmb = false;
      }
    }
    if (coordsChanged && surveyChanged) {
      // Parent pushed new TNGIS survey/sub-div from map tap.
      _tryAutoEcFill();
    }

    if (locationChanged && widget.district != null) {
      final match = _matchOption(_districts, widget.district);
      if (match != null && match.code != _selDistrict?.code) {
        _loadTaluks(match, autoFill: true);
      } else if (match != null) {
        // Same district but taluk/village changed — re-match down the chain.
        if (_taluks.isNotEmpty && widget.taluk != null) {
          final tMatch = _matchOption(_taluks, widget.taluk);
          if (tMatch != null && tMatch.code != _selTaluk?.code) {
            _loadVillages(tMatch, autoFill: true);
          }
        }
      }
      _tryAutoEcFill();
    } else if (surveyChanged) {
      // Same location, new survey number → dropdowns already populated, so just
      // fetch the documents directly.
      _maybeAutoFetchPatta();
      _maybeAutoFetchEc();
    }

    if (oldWidget.tngisSubdivisions != widget.tngisSubdivisions &&
        widget.tngisSubdivisions.isNotEmpty) {
      _syncSubdivisions(autoFetch: true);
    }

    final parcelReady = oldWidget.tngisParcelLoading && !widget.tngisParcelLoading;
    if ((parcelReady ||
            surveyChanged ||
            codesChanged ||
            (oldWidget.tngisSubdivisions != widget.tngisSubdivisions &&
                widget.tngisSubdivisions.isNotEmpty)) &&
        _selectedGiService == 'fmb' &&
        !widget.tngisParcelLoading) {
      Future.microtask(() {
        if (!mounted) return;
        _loadFmbForSelectedParcel();
      });
    }

    if (surveyChanged &&
        widget.surveyNumber != null &&
        widget.surveyNumber!.trim().isNotEmpty) {
      Future.microtask(() {
        if (!mounted) return;
        if (_selectedGiService == null) _onSelectGiService('patta');
      });
    }
  }

  void _syncSubdivisions({bool autoFetch = false}) {
    final visible = _visibleSubdivisionRows();
    final keys = visible.map((r) => r.key).toSet();
    _subdivBundles.removeWhere((k, _) => !keys.contains(k));
    for (final row in visible) {
      _subdivBundles.putIfAbsent(row.key, () => _SubdivDocBundle());
      if (autoFetch && row.containsPoint) {
        _fetchPattaForSubdivision(row);
      }
      if (autoFetch && _isSelectedFmbRow(row) && _hasFmbSubdivision(row)) {
        if (_selectedGiService == 'fmb') _fetchFmbForSubdivision(row);
      }
    }
  }

  /// Sub-division at the map tap — prefer view_fmb row containing the point.
  String? _resolvedMapSub() {
    for (final row in widget.tngisSubdivisions) {
      if (row.containsPoint && row.effectiveSubDivision != null) {
        return row.effectiveSubDivision;
      }
    }
    final sd = widget.subDivision?.trim();
    if (sd != null && sd.isNotEmpty && sd != '-' && sd != widget.surveyNumber?.trim()) {
      return sd;
    }
    return null;
  }

  _TngisSubdivisionRow? _containingSubdivisionRow() {
    for (final row in widget.tngisSubdivisions) {
      if (_isSelectedFmbRow(row) && _hasFmbSubdivision(row)) return row;
    }
    return null;
  }

  _TngisSubdivisionRow? _subdivisionRowForSub(String sub) {
    final norm = sub.trim().toUpperCase();
    for (final row in widget.tngisSubdivisions) {
      final rowSub = row.effectiveSubDivision?.trim().toUpperCase();
      if (rowSub != null && rowSub == norm) return row;
    }
    return null;
  }

  /// Sub-division rows to show in Patta/FMB UI — selected plot only.
  List<_TngisSubdivisionRow> _visibleSubdivisionRows() {
    return _TngisSubdivisionRow.filterForTap(
      widget.tngisSubdivisions,
      _resolvedMapSub() ?? widget.subDivision,
      widget.surveyNumber,
    );
  }

  /// Selected parcel survey + optional sub + TNGIS revenue codes for sketch_fmb.
  ({String survey, String? sub, String? dc, String? tc, String? vc})? _selectedParcelForFmb() {
    final survey = widget.surveyNumber?.trim();
    if (survey == null || survey.isEmpty) return null;
    final sub = _resolvedMapSub();

    String? dc = _nonEmptyCode(widget.districtCode);
    String? tc = _nonEmptyCode(widget.talukCode);
    String? vc = _nonEmptyCode(widget.villageCode);

    for (final row in widget.tngisSubdivisions) {
      if (sub != null && row.effectiveSubDivision != sub && !_isSelectedFmbRow(row)) continue;
      dc ??= _nonEmptyCode(row.fields['District Code']);
      tc ??= _nonEmptyCode(row.fields['Taluk Code']);
      vc ??= _nonEmptyCode(row.fields['Village Code']);
      if (dc != null && tc != null && vc != null) break;
    }

    final hasPoint = widget.lat != null && widget.lon != null;
    if ((dc == null || tc == null || vc == null) && !hasPoint) {
      return null;
    }
    return (survey: survey, sub: sub, dc: dc, tc: tc, vc: vc);
  }

  Future<void> _loadFmbForSelectedParcel() async {
    if (widget.tngisParcelLoading) {
      if (mounted) {
        setState(() {
          _loadingFmb = true;
          _fmbLoadError = null;
        });
      }
      return;
    }

    final parcel = _selectedParcelForFmb();
    if (parcel == null) {
      setState(() {
        _loadingFmb = false;
        final survey = widget.surveyNumber?.trim();
        if (survey == null || survey.isEmpty) {
          _fmbLoadError = 'Tap the map to select a land parcel.';
        } else {
          _fmbLoadError =
              'Parcel still loading — wait a moment, or tap the map on your plot.';
        }
      });
      return;
    }

    final row = parcel.sub != null
        ? (_subdivisionRowForSub(parcel.sub!) ?? _containingSubdivisionRow())
        : _containingSubdivisionRow();
    if (row != null && row.effectiveSubDivision != null) {
      await _fetchFmbForSubdivision(row);
      return;
    }
    await _fetchFmbDirect(
      survey: parcel.survey,
      sub: parcel.sub,
      dc: parcel.dc,
      tc: parcel.tc,
      vc: parcel.vc,
      kide: row?.kide,
    );
  }

  Future<void> _fetchPattaForSubdivision(_TngisSubdivisionRow row) async {
    final bundle = _subdivBundles[row.key] ??= _SubdivDocBundle();
    if (bundle.loadingPatta) return;
    setState(() => bundle.loadingPatta = true);
    try {
      final parts = <String>[];
      if (widget.lat != null && widget.lon != null) {
        parts.add('lat=${widget.lat}');
        parts.add('lon=${widget.lon}');
      }
      parts.add('surveyNo=${Uri.encodeComponent(row.surveyNumber)}');
      final sub = row.effectiveSubDivision;
      if (sub != null && sub.isNotEmpty && sub != '-') {
        parts.add('subDiv=${Uri.encodeComponent(sub)}');
      }
      final result = await ApiClient.get(
        '/api/tnlands/patta?${parts.join('&')}',
        timeout: const Duration(seconds: 120),
      );
      bundle.documents = result['documents'] as Map<String, dynamic>?;
      if (row.containsPoint) _applyPattaResult(result);
    } on ApiException catch (e) {
      if (row.containsPoint) setState(() => _pattaError = e.message);
    } catch (e) {
      if (row.containsPoint) {
        setState(() => _pattaError = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => bundle.loadingPatta = false);
    }
  }

  bool _hasFmbSubdivision(_TngisSubdivisionRow row) =>
      row.effectiveSubDivision != null;

  void _autoOpenFmbIfReady(
    Uint8List pdfBytes, {
    String? survey,
    String? sub,
  }) {
    if (_selectedGiService != 'fmb' || pdfBytes.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedGiService != 'fmb') return;
      _showFmbSketch(pdfBytes, survey: survey, sub: sub);
    });
  }

  void _showFmbSketch(
    Uint8List pdfBytes, {
    String? fileName,
    String? survey,
    String? sub,
  }) {
    final s = survey ?? widget.surveyNumber?.trim();
    final sd = sub ?? _resolvedMapSub() ?? widget.subDivision?.trim();
    final name = fileName ??
        'FMB${s != null ? '-$s' : ''}${sd != null ? '-Sub-$sd' : ''}.pdf';
    // Show the sketch inline — opening a new browser tab gets popup-blocked,
    // so the PDF appeared to "not show". The dialog still has an Open button.
    FmbSketchViewer.show(
      context,
      pdfBytes: pdfBytes,
      fileName: name,
      survey: s,
      subDivision: sd,
    );
  }

  static String? _nonEmptyCode(String? value) {
    final t = value?.trim();
    return (t != null && t.isNotEmpty) ? t : null;
  }

  /// Row matches the parcel the user selected on the map (not only strict polygon hit).
  bool _isSelectedFmbRow(_TngisSubdivisionRow row) {
    if (row.containsPoint) return true;
    final sub = _resolvedMapSub();
    if (sub != null &&
        row.effectiveSubDivision?.trim().toUpperCase() == sub.trim().toUpperCase()) {
      return true;
    }
    if (widget.tngisSubdivisions.length == 1) return true;
    return false;
  }

  String? _fmbApiPath({
    String? survey,
    String? sub,
    String? dc,
    String? tc,
    String? vc,
    String? kide,
  }) {
    final parts = <String>[];
    final hasPoint = widget.lat != null && widget.lon != null;
    if (hasPoint) {
      parts.add('lat=${widget.lat}');
      parts.add('lon=${widget.lon}');
    }

    final surveyNo = (survey ?? widget.surveyNumber)?.trim();
    if ((surveyNo == null || surveyNo.isEmpty) && !hasPoint) return null;

    final subDiv = (sub ?? _resolvedMapSub())?.trim();
    final validSub = subDiv != null &&
        subDiv.isNotEmpty &&
        subDiv != '-' &&
        subDiv != surveyNo;

    String? dcVal = _nonEmptyCode(dc) ?? _nonEmptyCode(widget.districtCode);
    String? tcVal = _nonEmptyCode(tc) ?? _nonEmptyCode(widget.talukCode);
    String? vcVal = _nonEmptyCode(vc) ?? _nonEmptyCode(widget.villageCode);
    if (dcVal == null || tcVal == null || vcVal == null) {
      for (final row in widget.tngisSubdivisions) {
        if (validSub && row.effectiveSubDivision != subDiv && !_isSelectedFmbRow(row)) {
          continue;
        }
        dcVal ??= _nonEmptyCode(row.fields['District Code']);
        tcVal ??= _nonEmptyCode(row.fields['Taluk Code']);
        vcVal ??= _nonEmptyCode(row.fields['Village Code']);
        if (dcVal != null && tcVal != null && vcVal != null) break;
      }
    }
    if (dcVal == null || tcVal == null || vcVal == null) {
      if (widget.lat == null || widget.lon == null) {
        return null;
      }
    } else {
      parts.add('dc=${Uri.encodeComponent(dcVal)}');
      parts.add('tc=${Uri.encodeComponent(tcVal)}');
      parts.add('vc=${Uri.encodeComponent(vcVal)}');
    }

    if (surveyNo != null && surveyNo.isNotEmpty) {
      parts.add('surveyNo=${Uri.encodeComponent(surveyNo)}');
    }
    if (validSub && surveyNo != null && surveyNo.isNotEmpty) {
      parts.add('subDiv=${Uri.encodeComponent(subDiv)}');
    }
    final kideVal = kide?.trim();
    if (kideVal != null && kideVal.isNotEmpty && kideVal.contains('/')) {
      parts.add('kide=${Uri.encodeComponent(kideVal)}');
    }
    return '/api/tnlands/fmb?${parts.join('&')}';
  }

  Future<void> _fetchFmbDirect({
    String? survey,
    String? sub,
    String? dc,
    String? tc,
    String? vc,
    String? kide,
  }) async {
    final path = _fmbApiPath(
      survey: survey,
      sub: sub,
      dc: dc,
      tc: tc,
      vc: vc,
      kide: kide,
    );
    if (path == null) {
      setState(() => _fmbLoadError =
          'Map location required. Tap directly on your plot and wait for parcel details.');
      return;
    }
    setState(() {
      _loadingFmb = true;
      _fmbLoadError = null;
    });
    try {
      final bytes = await ApiClient.getBytes(path);
      if (!mounted) return;
      final pdf = Uint8List.fromList(bytes);
      setState(() {
        _fmbPdfBytes = pdf;
        _loadingFmb = false;
      });
      _autoOpenFmbIfReady(pdf, survey: survey, sub: sub);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _fmbLoadError = e.message;
        _loadingFmb = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fmbLoadError = e.toString().replaceAll('Exception: ', '');
        _loadingFmb = false;
      });
    }
  }

  Future<void> _fetchFmbForSubdivision(_TngisSubdivisionRow row) async {
    final bundle = _subdivBundles[row.key] ??= _SubdivDocBundle();
    if (bundle.loadingFmb) return;
    final selected = _isSelectedFmbRow(row);
    setState(() {
      bundle.loadingFmb = true;
      bundle.fmbError = null;
      if (selected) {
        _loadingFmb = true;
        _fmbLoadError = null;
      }
    });
    try {
      final sub = row.effectiveSubDivision;
      final path = _fmbApiPath(
        survey: row.surveyNumber,
        sub: sub,
        dc: _nonEmptyCode(row.fields['District Code']) ?? widget.districtCode,
        tc: _nonEmptyCode(row.fields['Taluk Code']) ?? widget.talukCode,
        vc: _nonEmptyCode(row.fields['Village Code']) ?? widget.villageCode,
        kide: row.kide,
      );
      if (path == null) {
        throw const ApiException(
          statusCode: 400,
          message: 'Survey and map location required for FMB.',
        );
      }
      final bytes = await ApiClient.getBytes(path);
      bundle.fmbPdf = Uint8List.fromList(bytes);
      if (selected) {
        setState(() {
          _fmbPdfBytes = bundle.fmbPdf;
          _fmbLoadError = null;
        });
        _autoOpenFmbIfReady(
          bundle.fmbPdf!,
          survey: row.surveyNumber,
          sub: row.effectiveSubDivision,
        );
      }
    } on ApiException catch (e) {
      bundle.fmbError = e.message;
      if (selected) setState(() => _fmbLoadError = e.message);
    } catch (e) {
      bundle.fmbError = e.toString().replaceAll('Exception: ', '');
      if (selected) setState(() => _fmbLoadError = bundle.fmbError);
    } finally {
      if (mounted) {
        setState(() {
          bundle.loadingFmb = false;
          if (selected) _loadingFmb = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pattaDebounce?.cancel();
    _surveyCtrl.dispose(); _subDivCtrl.dispose();
    _ecSurveyCtrl.dispose(); _ecSubDivCtrl.dispose();
    _ecFromCtrl.dispose(); _ecToCtrl.dispose();
    _ecCaptchaCtrl.dispose();
    super.dispose();
  }

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  List<_Option> _toOptions(List<dynamic> data) => data.map((d) {
        final m = d as Map<String, dynamic>;
        return _Option(m['code'] as String, m['name'] as String);
      }).toList();

  /// Fuzzy-match a GPS name string against a dropdown option list.
  _Option? _matchOption(List<_Option> options, String? query) {
    if (query == null || query.isEmpty) return null;
    final q = query.toLowerCase().trim();
    for (final o in options) {
      if (o.name.toLowerCase() == q) return o;
    }
    for (final o in options) {
      final n = o.name.toLowerCase();
      if (n.contains(q) || q.contains(n)) return o;
    }
    final tokens = q.split(RegExp(r'[\s\-,/]+')).where((t) => t.length > 2).toList();
    for (final o in options) {
      final n = o.name.toLowerCase();
      if (tokens.any((t) => n.contains(t))) return o;
    }
    return null;
  }

  // â”€â”€ Patta methods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _applyPattaResult(Map<String, dynamic> result, {String? requestedSurvey}) {
    final fields = (result['fields'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v.toString()));
    final owners = (result['owners'] as List<dynamic>? ?? []).map((o) {
      return (o as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
    }).toList();

    final surveyNo = fields['Survey Number'];
    final reqSurvey = requestedSurvey?.trim();
    if (surveyNo != null && surveyNo.isNotEmpty) {
      if (reqSurvey == null || reqSurvey.isEmpty || surveyNo == reqSurvey) {
        _surveyCtrl.text = surveyNo;
        _ecSurveyCtrl.text = surveyNo;
      }
    }
    final subDiv = fields['Sub Division'];
    if (subDiv != null && subDiv.isNotEmpty && subDiv != '-') {
      _subDivCtrl.text = subDiv;
      _ecSubDivCtrl.text = subDiv;
    }

    setState(() {
      _pattaFields = fields.isEmpty ? null : fields;
      _pattaDocuments = result['documents'] as Map<String, dynamic>?;
      final patta = _pattaDocuments?['patta'] as Map<String, dynamic>?;
      if (patta != null && patta['official'] == true) {
        final docFields = patta['fields'] as Map<String, dynamic>?;
        if (docFields != null && docFields.isNotEmpty) {
          _pattaFields = docFields.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
      final pattaErr = patta?['error'] as String?;
      final hasPattaDoc = patta != null && patta['available'] == true
          && ((patta['html'] as String?)?.isNotEmpty == true
              || (patta['pdfBase64'] as String?)?.isNotEmpty == true);
      if (fields.isEmpty && owners.isEmpty && !hasPattaDoc
          && (patta == null || patta['available'] != true)) {
        _pattaError = pattaErr ?? (result['error'] as String?) ??
            'No patta parcel found at this location in TNGIS.';
      } else {
        _pattaError = hasPattaDoc ? null : (pattaErr ?? _pattaError);
      }
    });
    if (_selectedGiService == 'fmb') {
      _maybePrefetchFmbFromPattaDocs();
    }
  }

  Future<void> _maybePrefetchFmbFromPattaDocs() async {
    if (_fmbPdfBytes != null || _loadingFmb) return;
    final fmb = _pattaDocuments?['fmb'] as Map<String, dynamic>?;
    final url = fmb?['downloadUrl'] as String?;
    if (url == null || url.isEmpty) return;
    await _fetchFmbFromPath(url);
  }

  Future<void> _fetchFmbFromPath(String path) async {
    setState(() {
      _loadingFmb = true;
      _fmbLoadError = null;
    });
    try {
      final bytes = await ApiClient.getBytes(path);
      if (!mounted) return;
      final pdf = Uint8List.fromList(bytes);
      setState(() {
        _fmbPdfBytes = pdf;
        _loadingFmb = false;
      });
      _autoOpenFmbIfReady(pdf);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _fmbLoadError = e.message;
        _loadingFmb = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fmbLoadError = e.toString().replaceAll('Exception: ', '');
        _loadingFmb = false;
      });
    }
  }

  /// Fetch patta from TNGIS for the active map location (or device GPS).
  Future<void> _fetchPattaForLocation({bool useDeviceGps = false}) async {
    double? lat = useDeviceGps ? null : widget.lat;
    double? lon = useDeviceGps ? null : widget.lon;

    setState(() {
      _fetchingPatta = true;
      _pattaFields = null;
      _pattaError = null;
      _pattaDocuments = null;
      _fmbPdfBytes = null;
      _fmbLoadError = null;
    });

    if (lat == null || lon == null) {
      try {
        final svcOn = await Geolocator.isLocationServiceEnabled();
        if (!svcOn) {
          setState(() {
            _pattaError =
                'Tap the map to set a location, or enable GPS on your device.';
            _fetchingPatta = false;
          });
          return;
        }
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          setState(() {
            _pattaError = 'Tap the map to set a location, or allow GPS permission.';
            _fetchingPatta = false;
          });
          return;
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        );
        lat = pos.latitude;
        lon = pos.longitude;
      } catch (e) {
        setState(() {
          _pattaError =
              'Set a location on the map (tap the map), then tap Fetch Patta.';
          _fetchingPatta = false;
        });
        return;
      }
    }

    try {
      var params = 'lat=$lat&lon=$lon';
      final surveyNo = _surveyCtrl.text.trim();
      final subDiv = _subDivCtrl.text.trim();
      if (surveyNo.isNotEmpty) {
        params += '&surveyNo=${Uri.encodeComponent(surveyNo)}';
      }
      if (subDiv.isNotEmpty) {
        params += '&subDiv=${Uri.encodeComponent(subDiv)}';
      }
      final result = await ApiClient.get(
        '/api/tnlands/patta?$params',
        timeout: const Duration(seconds: 180),
      );
      _applyPattaResult(result, requestedSurvey: surveyNo);
    } on ApiException catch (e) {
      setState(() => _pattaError = e.message);
    } on TimeoutException {
      setState(() => _pattaError =
          'Government servers are slow (can take 1–2 min). Try again.');
    } catch (e) {
      setState(() =>
          _pattaError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _fetchingPatta = false);
    }
  }

  Future<void> _initDistricts() async {
    setState(() {});
    try {
      final data = await ApiClient.getList('/api/tnlands/districts');
      final loaded = _toOptions(data);
      setState(() {
        _districts = loaded.isNotEmpty ? loaded : _kStaticDistricts;
        if (widget.district != null) {
          _selDistrict = _matchOption(_districts, widget.district);
          if (_selDistrict != null) {
            Future.microtask(() => _loadTaluks(_selDistrict!, autoFill: true));
          }
        }
      });
    } catch (_) {
      // Fall back to static list but still try to auto-match the district
      setState(() {
        _districts = _kStaticDistricts;
        if (widget.district != null) {
          _selDistrict = _matchOption(_kStaticDistricts, widget.district);
          if (_selDistrict != null) {
            Future.microtask(() => _loadTaluks(_selDistrict!, autoFill: true));
          }
        }
      });
    } finally {
      setState(() {});
    }
  }

  Future<void> _loadTaluks(_Option district, {bool autoFill = false}) async {
    setState(() {
      _selDistrict = district;
      _taluks = []; _selTaluk = null;
_selVillage = null;
    });
    try {
      final data = await ApiClient.getList('/api/tnlands/taluks?dc=${district.code}');
      final loaded = _toOptions(data);
      setState(() { _taluks = loaded;  });
      if (autoFill && widget.taluk != null && loaded.isNotEmpty) {
        final match = _matchOption(loaded, widget.taluk);
        if (match != null) await _loadVillages(match, autoFill: true);
      }
    } catch (e) {
      setState(() {
      });
    }
  }

  Future<void> _loadVillages(_Option taluk, {bool autoFill = false}) async {
    setState(() {
      _selTaluk = taluk;
_selVillage = null;
    });
    try {
      final data = await ApiClient.getList(
          '/api/tnlands/villages?dc=${_selDistrict!.code}&tc=${taluk.code}');
      final loaded = _toOptions(data);
      setState(() {
        if (autoFill && widget.village != null && loaded.isNotEmpty) {
          _selVillage = _matchOption(loaded, widget.village);
        }
      });
      if (autoFill) _maybeAutoFetchPatta();
    } catch (e) {
      setState(() {
      });
    }
  }

  /// TNGIS lookup by survey number — uses map location when available.
  Future<void> _fetchPattaBySurveyNo() async {
    final surveyNo = _surveyCtrl.text.trim();
    if (surveyNo.isEmpty) return;

    setState(() {
      _fetchingPatta = true;
      _pattaFields = null;
      _pattaError = null;
      _pattaDocuments = null;
      _fmbPdfBytes = null;
      _fmbLoadError = null;
    });
    try {
      final subDiv = _subDivCtrl.text.trim();
      var params = 'surveyNo=${Uri.encodeComponent(surveyNo)}';
      if (subDiv.isNotEmpty) params += '&subDiv=${Uri.encodeComponent(subDiv)}';
      if (widget.lat != null && widget.lon != null) {
        params += '&lat=${widget.lat}&lon=${widget.lon}';
      }
      final result = await ApiClient.get(
        '/api/tnlands/patta?$params',
        timeout: const Duration(seconds: 180),
      );
      _applyPattaResult(result, requestedSurvey: surveyNo);
    } on ApiException catch (e) {
      setState(() => _pattaError = e.message);
    } on TimeoutException {
      setState(() => _pattaError =
          'Government servers are slow (can take 1–2 min). Try again.');
    } catch (e) {
      setState(() => _pattaError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _fetchingPatta = false);
    }
  }

  Future<void> _fetchPatta() async {
    if (_selDistrict == null || _selTaluk == null ||
        _selVillage == null || _surveyCtrl.text.trim().isEmpty) { return; }
    setState(() {
      _fetchingPatta = true;
      _pattaFields = null;
      _pattaError = null;
      _pattaDocuments = null;
      _fmbPdfBytes = null;
      _fmbLoadError = null;
    });
    try {
      var params = 'dc=${_selDistrict!.code}'
          '&tc=${_selTaluk!.code}'
          '&vc=${_selVillage!.code}'
          '&surveyNo=${Uri.encodeComponent(_surveyCtrl.text.trim())}'
          '&subDiv=${Uri.encodeComponent(_subDivCtrl.text.trim())}';
      if (widget.lat != null && widget.lon != null) {
        params += '&lat=${widget.lat}&lon=${widget.lon}';
      }
      final result = await ApiClient.get(
        '/api/tnlands/patta?$params',
        timeout: const Duration(seconds: 180),
      );
      _applyPattaResult(result);
    } on ApiException catch (e) {
      setState(() => _pattaError = e.message);
    } on TimeoutException {
      setState(() => _pattaError =
          'Government servers are slow (can take 1–2 min). Try again.');
    } catch (e) {
      setState(() => _pattaError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _fetchingPatta = false);
    }
  }

  // â”€â”€ EC methods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadEcZones() async {
    try {
      final data = await ApiClient.getList('/api/tnlands/ec/zones');
      final loaded = _toOptions(data);
      if (loaded.isNotEmpty) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadEcCaptcha() async {
    setState(() {});
    try {
      final result = await ApiClient.get('/api/tnlands/ec/captcha');
      setState(() {
        _ecCaptchaSession = result['sessionId'] as String?;
        _ecCaptchaCtrl.clear();
      });
    } catch (e) {
      setState(() => _ecError = 'Could not load EC captcha. Tap refresh to retry.');
    } finally {
      setState(() {});
    }
  }

  // ── EC methods ─────────────────────────────────────────────────────────────

  Future<void> _loadEcPeriods() async {
    setState(() {});
    try {
      final data = await ApiClient.getList('/api/tnlands/ec/periods');
      final loaded = data.map((d) => _EcPeriod.fromJson(d as Map<String, dynamic>)).toList();
      setState(() {
        _ecPeriods = loaded;
        _selEcPeriod ??= loaded.isNotEmpty ? loaded.first : null;
      });
    } catch (_) {
      final now = DateTime.now();
      final y = now.year;
      setState(() {
        _ecPeriods = [
          _EcPeriod('$y', '$y', '01/01/$y', '31/12/$y'),
          const _EcPeriod('full', 'Full period (2000–today)', '01/01/2000', ''),
        ];
        if (_ecPeriods.last.toDate.isEmpty) {
          final t = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/$y';
          _ecPeriods = [
            _EcPeriod('$y', '$y ($t)', '01/01/$y', '31/12/$y'),
            _EcPeriod('full', 'Full period', '01/01/2000', t),
          ];
        }
        _selEcPeriod ??= _ecPeriods.first;
      });
    } finally {
      setState(() {});
    }
  }

  void _applyEcSearchResult(Map<String, dynamic> result) {
    final records = (result['records'] as List<dynamic>? ?? []).map((r) {
      return (r as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
    }).toList();
    final entries = (result['entries'] as List<dynamic>? ?? []).map((e) {
      final m = e as Map<String, dynamic>;
      return _EcEntry(m['id'] as String, m['label'] as String);
    }).toList();
    final doc = result['document'] as Map<String, dynamic>?;
    final meta = (result['meta'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v.toString()));
    final pdfB64 = doc?['pdfBase64'] as String?;
    Uint8List? pdfBytes;
    if (pdfB64 != null && pdfB64.isNotEmpty) {
      try {
        pdfBytes = Uint8List.fromList(base64.decode(pdfB64));
      } catch (_) {}
    }

    setState(() {
      _ecSource = result['source'] as String?;
      _ecAllRecords = records;
      _selEcEntryId = entries.length == 1 ? entries.first.id : 'all';
      _ecMeta = meta;
      _ecDocumentHtml = doc?['html'] as String?;
      _ecPdfBytes = pdfBytes;
      _ecPdfFileName = doc?['pdfFileName'] as String?;
      final msg = result['message'] as String?;
      final hasPdf = pdfBytes != null && pdfBytes.isNotEmpty;
      final hasHtml = (_ecDocumentHtml?.length ?? 0) > 200;
      _ecError = (records.isEmpty && !hasPdf && !hasHtml)
          ? (msg ?? 'No EC records for this period.')
          : null;
    });
    _refreshEcEntryPreview();
  }

  String _buildEcHtmlForRecords(List<Map<String, String>> records) {
    if (records.isEmpty) return '<p>No records</p>';
    final headers = records.first.keys.toList();
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final metaRows = _ecMeta.entries
        .map((e) => '<tr><th>${esc(e.key)}</th><td>${esc(e.value)}</td></tr>')
        .join();
    final headerRow = headers.map((h) => '<th>${esc(h)}</th>').join();
    final bodyRows = records.map((r) {
      return '<tr>${headers.map((h) => '<td>${esc(r[h] ?? '')}</td>').join()}</tr>';
    }).join();
    return '''<!DOCTYPE html><html><head><meta charset="utf-8"><style>
      body{font-family:Georgia,serif;margin:20px;color:#111}
      h1{font-size:18px;color:#C62828}
      table{border-collapse:collapse;width:100%;margin:12px 0;font-size:12px}
      th,td{border:1px solid #ccc;padding:6px 8px;text-align:left}
      th{background:#ffebee}
    </style></head><body>
    <h1>Encumbrance Certificate (EC)</h1>
    <p style="font-size:11px;color:#555">Source: tnreginet.gov.in</p>
    <table>$metaRows</table>
    <table><thead><tr>$headerRow</tr></thead><tbody>$bodyRows</tbody></table>
    </body></html>''';
  }

  void _refreshEcEntryPreview() {
    if (_ecAllRecords.isEmpty) return;
    List<Map<String, String>> show = _ecAllRecords;
    if (_selEcEntryId != null && _selEcEntryId != 'all') {
      final idx = int.tryParse(_selEcEntryId!);
      if (idx != null && idx >= 0 && idx < _ecAllRecords.length) {
        show = [_ecAllRecords[idx]];
      }
    }
    setState(() => _ecDocumentHtml = _buildEcHtmlForRecords(show));
  }

  Future<bool> _resolveEcFromServer({
    String? district,
    String? taluk,
    String? village,
  }) async {
    setState(() {  _ecError = null; });

    var params = '';
    if (widget.lat != null && widget.lon != null) {
      params = 'lat=${widget.lat}&lon=${widget.lon}';
    }
    final dist = district ?? widget.district ?? _pattaFields?['District'];
    final tk = taluk ?? widget.taluk ?? _pattaFields?['Taluk'];
    final vill = village ?? widget.village ?? _pattaFields?['Village'];
    if (dist != null && dist.isNotEmpty) {
      params += '${params.isEmpty ? '' : '&'}district=${Uri.encodeComponent(dist)}';
    }
    if (tk != null && tk.isNotEmpty) {
      params += '&taluk=${Uri.encodeComponent(tk)}';
    }
    if (vill != null && vill.isNotEmpty) {
      params += '&village=${Uri.encodeComponent(vill)}';
    }

    if (params.isEmpty) {
      setState(() {
        _ecError = 'Set a map location first (tap the map).';
      });
      return false;
    }

    try {
      final result = await ApiClient.get(
        '/api/tnlands/ec/resolve?$params',
        timeout: const Duration(seconds: 45),
      );
      final zone = result['zone'] as Map<String, dynamic>?;
      final distObj = result['district'] as Map<String, dynamic>?;
      final sros = (result['sros'] as List<dynamic>? ?? [])
          .map((s) => _Option(s['code'] as String, s['name'] as String))
          .toList();
      final suggested = result['suggestedSro'] as Map<String, dynamic>?;

      if (zone == null || distObj == null || sros.isEmpty) {
        setState(() {
          _ecError = 'Could not load SRO list for this district.';
        });
        return false;
      }

      setState(() {
        _selZone = _Option(zone['code'] as String, zone['name'] as String);
        _selEcDist = _Option(distObj['code'] as String, distObj['name'] as String);
        _ecSros = sros;
        _selEcSro = suggested != null
            ? _Option(suggested['code'] as String, suggested['name'] as String)
            : sros.first;
        _ecError = null;
      });
      return true;
    } on ApiException catch (e) {
      setState(() {
        _ecError = e.message;
      });
      return false;
    } catch (e) {
      setState(() {
        _ecError = e.toString().replaceAll('Exception: ', '');
      });
      return false;
    } finally {
      setState(() {});
    }
  }

  Future<void> _searchEcWithPeriod(_EcPeriod period, {bool tryAlternateSros = true}) async {
    _ecFromCtrl.text = period.fromDate;
    _ecToCtrl.text = period.toDate;
    if (_selZone == null || _selEcDist == null || _selEcSro == null ||
        _ecSurveyCtrl.text.trim().isEmpty) {
      setState(() {
        _ecError = 'Survey number and SRO are required. Fetch patta first or enter survey no.';
        _fetchingEc = false;
      });
      return;
    }
    setState(() { _fetchingEc = true; _ecError = null; });
    try {
      if (_ecCaptchaSession == null || _ecCaptchaCtrl.text.trim().isEmpty) {
        setState(() {
          _ecError = 'Enter the captcha code from the image below.';
          _fetchingEc = false;
        });
        return;
      }
      var params = 'zone=${_selZone!.code}'
          '&dc=${_selEcDist!.code}'
          '&sro=${Uri.encodeComponent(_selEcSro!.code)}'
          '&surveyNo=${Uri.encodeComponent(_ecSurveyCtrl.text.trim())}'
          '&subDiv=${Uri.encodeComponent(_ecSubDivCtrl.text.trim())}'
          '&fromDate=${Uri.encodeComponent(period.fromDate)}'
          '&toDate=${Uri.encodeComponent(period.toDate)}'
          '&districtName=${Uri.encodeComponent(_selEcDist!.name)}'
          '&sroName=${Uri.encodeComponent(_selEcSro!.name)}'
          '&ecSession=${Uri.encodeComponent(_ecCaptchaSession!)}'
          '&captcha=${Uri.encodeComponent(_ecCaptchaCtrl.text.trim())}';
      if (widget.village != null && widget.village!.isNotEmpty) {
        params += '&villageName=${Uri.encodeComponent(widget.village!)}';
      } else if (_pattaFields?['Village'] != null) {
        params += '&villageName=${Uri.encodeComponent(_pattaFields!['Village']!)}';
      }
      final result = await ApiClient.get(
        '/api/tnlands/ec/search?$params',
        timeout: const Duration(seconds: 90),
      );
      final count = result['count'] as int? ?? 0;
      final doc = result['document'] as Map<String, dynamic>?;
      final hasPdf = (doc?['pdfBase64'] as String?)?.isNotEmpty == true;
      if (tryAlternateSros &&
          count == 0 &&
          !hasPdf &&
          _ecSros.length > 1) {
        final startIdx = _ecSros.indexWhere((s) => s.code == _selEcSro?.code);
        for (var i = 0; i < _ecSros.length && i < 10; i++) {
          if (i == startIdx) continue;
          final altSro = _ecSros[i];
          setState(() => _selEcSro = altSro);
          var altParams = 'zone=${_selZone!.code}'
              '&dc=${_selEcDist!.code}'
              '&sro=${Uri.encodeComponent(altSro.code)}'
              '&surveyNo=${Uri.encodeComponent(_ecSurveyCtrl.text.trim())}'
              '&subDiv=${Uri.encodeComponent(_ecSubDivCtrl.text.trim())}'
              '&fromDate=${Uri.encodeComponent(period.fromDate)}'
              '&toDate=${Uri.encodeComponent(period.toDate)}'
              '&districtName=${Uri.encodeComponent(_selEcDist!.name)}'
              '&sroName=${Uri.encodeComponent(altSro.name)}'
              '&ecSession=${Uri.encodeComponent(_ecCaptchaSession!)}'
              '&captcha=${Uri.encodeComponent(_ecCaptchaCtrl.text.trim())}';
          if (widget.village != null && widget.village!.isNotEmpty) {
            altParams += '&villageName=${Uri.encodeComponent(widget.village!)}';
          } else if (_pattaFields?['Village'] != null) {
            altParams += '&villageName=${Uri.encodeComponent(_pattaFields!['Village']!)}';
          }
          try {
            final altResult = await ApiClient.get(
              '/api/tnlands/ec/search?$altParams',
              timeout: const Duration(seconds: 90),
            );
            final altCount = altResult['count'] as int? ?? 0;
            final altDoc = altResult['document'] as Map<String, dynamic>?;
            if (altCount > 0 || (altDoc?['pdfBase64'] as String?)?.isNotEmpty == true) {
              _applyEcSearchResult(altResult);
              await _loadEcCaptcha();
              return;
            }
          } on ApiException catch (_) {}
        }
      }
      _applyEcSearchResult(result);
      await _loadEcCaptcha();
    } on ApiException catch (e) {
      if (tryAlternateSros &&
          e.statusCode == 404 &&
          _ecSros.length > 1) {
        final startIdx = _ecSros.indexWhere((s) => s.code == _selEcSro?.code);
        for (var i = 0; i < _ecSros.length && i < 10; i++) {
          if (i == startIdx) continue;
          setState(() => _selEcSro = _ecSros[i]);
          try {
            await _searchEcWithPeriod(period, tryAlternateSros: false);
            return;
          } on ApiException catch (_) {}
        }
      }
      setState(() => _ecError = e.message);
      if (e.statusCode == 400) await _loadEcCaptcha();
    } catch (e) {
      setState(() => _ecError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _fetchingEc = false);
    }
  }

  Future<void> _tryAutoEcFill() async {
    if (widget.district == null && widget.lat == null) return;
    await _resolveEcFromServer();
  }

  Future<void> _searchEc() async {
    if (_selEcPeriod != null) {
      await _searchEcWithPeriod(_selEcPeriod!);
      return;
    }
    if (_selZone == null || _selEcDist == null || _selEcSro == null ||
        _ecSurveyCtrl.text.trim().isEmpty ||
        _ecFromCtrl.text.trim().isEmpty || _ecToCtrl.text.trim().isEmpty) {
      setState(() => _ecError = 'Fill all fields before searching.');
      return;
    }
    setState(() { _fetchingEc = true;  _ecError = null; });
    try {
      if (_ecCaptchaSession == null || _ecCaptchaCtrl.text.trim().isEmpty) {
        setState(() {
          _ecError = 'Enter the captcha code from the image below.';
          _fetchingEc = false;
        });
        return;
      }
      final params = 'zone=${_selZone!.code}'
          '&dc=${_selEcDist!.code}'
          '&sro=${Uri.encodeComponent(_selEcSro!.code)}'
          '&surveyNo=${Uri.encodeComponent(_ecSurveyCtrl.text.trim())}'
          '&subDiv=${Uri.encodeComponent(_ecSubDivCtrl.text.trim())}'
          '&fromDate=${Uri.encodeComponent(_ecFromCtrl.text.trim())}'
          '&toDate=${Uri.encodeComponent(_ecToCtrl.text.trim())}'
          '&districtName=${Uri.encodeComponent(_selEcDist!.name)}'
          '&sroName=${Uri.encodeComponent(_selEcSro!.name)}'
          '&ecSession=${Uri.encodeComponent(_ecCaptchaSession!)}'
          '&captcha=${Uri.encodeComponent(_ecCaptchaCtrl.text.trim())}';
      final result = await ApiClient.get(
        '/api/tnlands/ec/search?$params',
        timeout: const Duration(seconds: 90),
      );
      _applyEcSearchResult(result);
      await _loadEcCaptcha();
    } on ApiException catch (e) {
      setState(() => _ecError = e.message);
      if (e.statusCode == 400) await _loadEcCaptcha();
    } catch (e) {
      setState(() => _ecError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _fetchingEc = false);
    }
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Government Records',
      subtitle: 'Patta, FMB, EC, G-Value and Crop from TNGIS',
      icon: Icons.layers_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TngisParcelSummary(
          parcel: TngisParcelDetails(
            district: widget.district,
            taluk: widget.taluk,
            village: widget.village,
            districtCode: widget.districtCode,
            talukCode: widget.talukCode,
            villageCode: widget.villageCode,
            ulpin: widget.ulpin,
            centroid: widget.centroid,
            ruralUrban: widget.ruralUrban,
            surveyNumber: widget.surveyNumber,
            subDivision: widget.subDivision,
          ),
          loading: widget.tngisParcelLoading,
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.isDarkMode
                ? AppColors.primary.withValues(alpha: 0.16)
                : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(AppColors.radiusSm),
            border: Border.all(
              color: context.isDarkMode
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : const Color(0xFFBFDBFE),
            ),
          ),
          child: Text(
            'Patta, FMB, EC, G-Value and Crop from the official TNGIS GI Viewer (Tamil Nilam).',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.isDarkMode
                  ? AppColors.primaryLight
                  : const Color(0xFF1D4ED8),
            ),
          ),
        ),
        if (widget.tngisGiViewerUrl != null && widget.tngisGiViewerUrl!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final uri = Uri.parse(widget.tngisGiViewerUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Open in TNGIS GI Viewer',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _buildGiServiceBoxes(),
        if (_selectedGiService != null) ...[
          const SizedBox(height: 14),
          _buildGiServiceDetail(_selectedGiService!),
        ] else ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.fomraSurfaceVar,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.fomraBorder),
            ),
            child: Text(
              'Tap Patta, FMB, EC, G-Value, or Crop above — data is fetched from TNGIS GI Viewer APIs.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildGiServiceBoxes() {
    return LayoutBuilder(builder: (context, constraints) {
      Widget boxFor(({
        String id,
        String label,
        IconData icon,
        Color color,
      }) svc, {bool isLast = false}) {
        final selected = _selectedGiService == svc.id;
        final card = widget.giServices?[svc.id] as Map?;
        final summary = card?['summary']?.toString().trim();
        final available = card?['available'] != false;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 6),
            child: Material(
              color: selected ? svc.color.withValues(alpha: 0.14) : context.fomraSurface,
              elevation: selected ? 2 : 0,
              shadowColor: svc.color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () => _onSelectGiService(svc.id),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? svc.color : svc.color.withValues(alpha: 0.4),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(svc.icon, color: svc.color, size: 28),
                    const SizedBox(height: 6),
                    Text(svc.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: svc.color,
                        )),
                    if (summary != null && summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 8,
                              height: 1.2,
                              color: svc.color.withValues(alpha: 0.8))),
                    ] else if (!available) ...[
                      const SizedBox(height: 4),
                      Text('N/A',
                          style: TextStyle(
                              fontSize: 8, color: context.fomraTextTertiary)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        );
      }

      if (constraints.maxWidth >= 520) {
        return Row(
          children: [
            for (var i = 0; i < _kGiServices.length; i++)
              boxFor(_kGiServices[i], isLast: i == _kGiServices.length - 1),
          ],
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _kGiServices.map((svc) {
            final selected = _selectedGiService == svc.id;
            final card = widget.giServices?[svc.id] as Map?;
            final summary = card?['summary']?.toString().trim();
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 88,
                child: Material(
                  color: selected ? svc.color.withValues(alpha: 0.14) : context.fomraSurface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => _onSelectGiService(svc.id),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? svc.color : svc.color.withValues(alpha: 0.4),
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Column(children: [
                        Icon(svc.icon, color: svc.color, size: 26),
                        const SizedBox(height: 4),
                        Text(svc.label,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: svc.color)),
                        if (summary != null && summary.isNotEmpty)
                          Text(summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 8, color: svc.color.withValues(alpha: 0.8))),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    });
  }

  Future<void> _onSelectGiService(String id) async {
    if (_selectedGiService == id) {
      setState(() => _selectedGiService = null);
      return;
    }
    setState(() {
      _selectedGiService = id;
      if (id != 'crop') _selectedCropSeason = null;
    });
    await _loadGiService(id);
  }

  Future<void> _loadGiService(String id) async {
    switch (id) {
      case 'patta':
        if (widget.tngisSubdivisions.isNotEmpty) {
          _syncSubdivisions(autoFetch: true);
        } else if (widget.lat != null && widget.lon != null) {
          await _fetchPattaForLocation();
        }
        break;
      case 'fmb':
        await _loadFmbForSelectedParcel();
        break;
      case 'ec':
        await _fetchGiEcFromTngis();
        break;
      case 'gvalue':
        await _fetchGiDetail('gvalue');
        break;
      case 'crop':
        await _fetchGiDetail('crop');
        break;
    }
  }

  Future<void> _fetchGiDetail(String type) async {
    if (widget.lat == null || widget.lon == null) {
      setState(() {
        if (type == 'gvalue') _gvalueError = 'Tap the map to set a plot location.';
        if (type == 'crop') _cropError = 'Tap the map to set a plot location.';
      });
      return;
    }
    setState(() {
      if (type == 'gvalue') {
        _loadingGvalue = true;
        _gvalueError = null;
      } else {
        _loadingCrop = true;
        _cropError = null;
      }
    });
    try {
      final parts = <String>[
        'lat=${widget.lat}',
        'lon=${widget.lon}',
        'type=$type',
      ];
      final survey = widget.surveyNumber?.trim();
      final sub = widget.subDivision?.trim();
      if (survey != null && survey.isNotEmpty) {
        parts.add('surveyNo=${Uri.encodeComponent(survey)}');
      }
      if (sub != null && sub.isNotEmpty && sub != '-') {
        parts.add('subDiv=${Uri.encodeComponent(sub)}');
      }
      final data = await ApiClient.get('/api/tnlands/tngis/gi-detail?${parts.join('&')}');
      setState(() {
        if (type == 'gvalue') {
          _gvalueData = data;
          _gvalueError = null;
        } else {
          _cropData = data;
          _cropError = null;
        }
      });
    } on ApiException catch (e) {
      setState(() {
        if (type == 'gvalue') _gvalueError = e.message;
        if (type == 'crop') _cropError = e.message;
      });
    } catch (e) {
      setState(() {
        final msg = e.toString().replaceAll('Exception: ', '');
        if (type == 'gvalue') _gvalueError = msg;
        if (type == 'crop') _cropError = msg;
      });
    } finally {
      setState(() {
        if (type == 'gvalue') _loadingGvalue = false;
        if (type == 'crop') _loadingCrop = false;
      });
    }
  }

  Widget _buildGiServiceDetail(String id) {
    final svc = _kGiServices.firstWhere((s) => s.id == id);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: svc.color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: svc.color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${svc.label} details',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: svc.color)),
        const SizedBox(height: 10),
        switch (id) {
          'patta' => _buildGiPattaDetail(),
          'fmb' => _buildGiFmbDetail(),
          'ec' => _buildGiEcDetail(),
          'gvalue' => _buildGiGvalueDetail(),
          'crop' => _buildGiCropDetail(),
          _ => const SizedBox.shrink(),
        },
      ]),
    );
  }

  Widget _buildGiPattaDetail() {
    if (_fetchingPatta) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    if (widget.tngisSubdivisions.isNotEmpty) {
      final visible = _visibleSubdivisionRows();
      return Column(
        children: visible.map((row) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildGiSubdivisionPreview(row),
        )).toList(),
      );
    }
    final patta = _pattaDocuments?['patta'] as Map<String, dynamic>?;
    if (_hasPattaPdf(patta)) {
      return _buildPattaDocPreview(patta, title: 'Patta / Chitta', pdfOnly: true);
    }
    if (_pattaError != null) {
      return Text(_pattaError!, style: TextStyle(fontSize: 11, color: Colors.orange.shade900));
    }
    return _buildGiNoResult();
  }

  bool _hasPattaPdf(Map<String, dynamic>? patta) {
    final pdf = patta?['pdfBase64'] as String?;
    return patta?['available'] == true && pdf != null && pdf.isNotEmpty;
  }

  Widget _buildGiNoResult([String message = 'No result found for this plot.']) {
    return Text(message, style: TextStyle(fontSize: 11, color: context.fomraTextSecondary));
  }

  Widget _buildGiFmbDetail() {
    if (widget.tngisParcelLoading) {
      return Column(children: [
        const Center(child: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        )),
        const SizedBox(height: 6),
        Text(
          'Resolving plot at tap point…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
        ),
      ]);
    }
    final visible = _visibleSubdivisionRows();
    final loading = visible.any((r) => (_subdivBundles[r.key]?.loadingFmb ?? false))
        || _loadingFmb;
    if (loading) {
      return Column(children: [
        const Center(child: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        )),
        const SizedBox(height: 6),
        Text(
          'Fetching FMB for Survey ${widget.surveyNumber ?? '—'} · Sub ${_resolvedMapSub() ?? widget.subDivision ?? '—'}…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
        ),
      ]);
    }

    Uint8List? pdfBytes = _fmbPdfBytes;
    String fileName = 'FMB Sketch.pdf';
    if (pdfBytes == null && visible.isNotEmpty) {
      for (final row in visible) {
        if (!_isSelectedFmbRow(row)) continue;
        final bundle = _subdivBundles[row.key];
        if (bundle?.fmbPdf != null) {
          pdfBytes = bundle!.fmbPdf;
          fileName = 'FMB Survey ${row.surveyNumber} Sub ${row.subLabel}.pdf';
          break;
        }
      }
      pdfBytes ??= visible
          .where(_isSelectedFmbRow)
          .map((r) => _subdivBundles[r.key]?.fmbPdf)
          .firstWhere((b) => b != null, orElse: () => null);
      if (pdfBytes != null && fileName == 'FMB Sketch.pdf') {
        for (final row in visible) {
          if (_subdivBundles[row.key]?.fmbPdf == pdfBytes) {
            fileName = 'FMB Survey ${row.surveyNumber} Sub ${row.subLabel}.pdf';
            break;
          }
        }
      }
    }

    if (pdfBytes != null && pdfBytes.isNotEmpty) {
      final sub = _resolvedMapSub() ?? widget.subDivision?.trim();
      final survey = widget.surveyNumber?.trim();
      final fileName = 'FMB${survey != null ? '-$survey' : ''}${sub != null ? '-Sub-$sub' : ''}.pdf';
      final title = sub != null && sub.isNotEmpty && sub != '-'
          ? 'FMB Sketch · Survey ${survey ?? ''} · Sub $sub'
          : 'FMB Sketch · Survey ${survey ?? ''} (general)';
      final subtitle = sub != null && sub.isNotEmpty && sub != '-'
          ? 'TNGIS / CollabLand sketch · ${(pdfBytes.length / 1024).round()} KB'
          : 'General survey FMB · ${(pdfBytes.length / 1024).round()} KB';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFmbSketchButton(
            title: title,
            subtitle: subtitle,
            onTap: () => _showFmbSketch(pdfBytes!, fileName: fileName),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the card above to open full screen, or use Open in new tab inside the viewer.',
            style: TextStyle(fontSize: 10, color: context.fomraTextSecondary, height: 1.35),
          ),
        ],
      );
    }

    if (_fmbLoadError != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_fmbLoadError!, style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _loadFmbForSelectedParcel,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Retry FMB', style: TextStyle(fontSize: 11)),
        ),
      ]);
    }

    for (final row in _visibleSubdivisionRows()) {
      final err = _subdivBundles[row.key]?.fmbError;
      if (err != null) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(err, style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _fetchFmbForSubdivision(row),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry FMB', style: TextStyle(fontSize: 11)),
          ),
        ]);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!widget.fmbAvailable && widget.fmbNote != null) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Text(
            widget.fmbNote!,
            style: TextStyle(fontSize: 10, color: Colors.amber.shade900, height: 1.35),
          ),
        ),
      ],
      Text(
        widget.surveyNumber != null
            ? _resolvedMapSub() != null
                ? 'Survey ${widget.surveyNumber} · Sub ${_resolvedMapSub()} — tap Load FMB to fetch sketch.'
                : 'Survey ${widget.surveyNumber} — no sub-division; will load general survey FMB.'
            : widget.lat == null
                ? 'Tap the map to select a land parcel, then open FMB.'
                : 'Waiting for survey and sub-division. Tap directly on your plot.',
        style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
      ),
      if (widget.surveyNumber != null) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _loadFmbForSelectedParcel,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: const Text('Load FMB', style: TextStyle(fontSize: 11)),
        ),
      ],
    ]);
  }

  Future<void> _fetchGiEcFromTngis() async {
    if (widget.lat == null || widget.lon == null) {
      setState(() => _ecError = 'Tap the map to set a plot location.');
      return;
    }
    setState(() {
      _fetchingEc = true;
      _ecError = null;
      _ecDocumentHtml = null;
      _ecPdfBytes = null;
      _ecAllRecords = [];
    });
    try {
      final parts = <String>[
        'lat=${widget.lat}',
        'lon=${widget.lon}',
      ];
      final survey = widget.surveyNumber?.trim();
      final sub = widget.subDivision?.trim();
      if (survey != null && survey.isNotEmpty) {
        parts.add('surveyNo=${Uri.encodeComponent(survey)}');
      }
      if (sub != null && sub.isNotEmpty && sub != '-') {
        parts.add('subDiv=${Uri.encodeComponent(sub)}');
      }
      final result = await ApiClient.get(
        '/api/tnlands/tngis/ec?${parts.join('&')}',
        timeout: const Duration(seconds: 90),
      );
      final doc = result['document'] as Map<String, dynamic>?;
      final pdfB64 = doc?['pdfBase64'] as String?;
      if (pdfB64 != null && pdfB64.isNotEmpty) {
        setState(() {
          _ecSource = result['source']?.toString() ?? 'TNGIS GI Viewer';
          _ecPdfBytes = Uint8List.fromList(base64.decode(pdfB64));
          _ecPdfFileName = doc?['pdfFileName']?.toString() ?? 'Encumbrance Certificate.pdf';
          _ecError = null;
        });
      } else {
        setState(() => _ecError = result['error']?.toString()
            ?? 'No Encumbrance Certificate found for this survey.');
      }
    } on ApiException catch (e) {
      setState(() => _ecError = e.message);
    } catch (e) {
      setState(() => _ecError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _fetchingEc = false);
    }
  }

  Widget _buildFmbSketchButton({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final cardBg = context.isDarkMode
        ? const Color(0xFF1A237E).withValues(alpha: 0.22)
        : const Color(0xFFE8EAF6);
    final cardBorder = context.isDarkMode
        ? AppColors.primaryLight.withValues(alpha: 0.35)
        : const Color(0xFF3949AB).withValues(alpha: 0.35);
    final iconBg = context.isDarkMode
        ? AppColors.primaryLight.withValues(alpha: 0.14)
        : const Color(0xFF1A237E).withValues(alpha: 0.12);
    final iconColor =
        context.isDarkMode ? AppColors.primaryLight : const Color(0xFF1A237E);

    // The whole card is the button — tapping anywhere opens the PDF.
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(AppColors.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppColors.radiusSm),
            border: Border.all(color: cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.picture_as_pdf_outlined, color: iconColor, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_outlined, color: iconColor, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'View as PDF',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPattaDocPreview(Map<String, dynamic>? patta, {String? title, bool pdfOnly = false}) {
    if (patta == null) return pdfOnly ? _buildGiNoResult() : const SizedBox.shrink();
    final pdfB64 = patta['pdfBase64'] as String?;
    if (patta['available'] == true && pdfB64 != null && pdfB64.isNotEmpty) {
      try {
        return PattaDocumentPreview(
          pdfBytes: Uint8List.fromList(base64.decode(pdfB64)),
          fileName: patta['fileName']?.toString() ?? 'Patta.pdf',
        );
      } catch (_) {}
    }
    if (pdfOnly) {
      if (patta['error'] != null) {
        return Text(patta['error'].toString(),
            style: TextStyle(fontSize: 11, color: Colors.orange.shade900));
      }
      return _buildGiNoResult();
    }
    final html = patta['html'] as String?;
    if (patta['available'] == true && html != null && html.isNotEmpty) {
      return PattaHtmlPreview(
        key: ValueKey('patta-html-${html.hashCode}'),
        html: html,
        title: title ?? 'Patta / Chitta (TNGIS Tamil Nilam)',
      );
    }
    if (patta['error'] != null) {
      return Text(patta['error'].toString(),
          style: TextStyle(fontSize: 11, color: Colors.orange.shade900));
    }
    return Text(
      'Patta not available from TNGIS for this plot.',
      style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
    );
  }

  Widget _buildGiEcDetail() {
    if (_fetchingEc) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    if (_ecError != null) {
      return Text(_ecError!, style: TextStyle(fontSize: 11, color: Colors.orange.shade900));
    }
    if (_ecPdfBytes != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Encumbrance Certificate',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(_ecSource ?? 'TNGIS GI Viewer',
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        PattaDocumentPreview(
          pdfBytes: _ecPdfBytes,
          fileName: _ecPdfFileName ?? 'Encumbrance Certificate.pdf',
        ),
      ]);
    }
    return Text(
      'Tap EC again after selecting a plot on the map.',
      style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
    );
  }

  Widget _buildGiInfoCard(String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.fomraSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.fomraBorder),
        boxShadow: context.fomraCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: context.fomraTextSecondary)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.fomraTextPrimary)),
      ]),
    );
  }

  Widget _buildGiGvalueDetail() {
    if (_loadingGvalue) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    if (_gvalueError != null) {
      return Text(_gvalueError!, style: TextStyle(fontSize: 11, color: Colors.orange.shade900));
    }
    if (_gvalueData == null) return const SizedBox.shrink();

    final items = (_gvalueData!['items'] as List<dynamic>? ?? []);
    if (items.isEmpty) {
      return Text(
        _gvalueData!['error']?.toString() ?? 'Guideline Value not found for the selected Land',
        style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        _gvalueData!['title']?.toString() ?? 'Guide Line Value from Registration Department',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      for (final raw in items) ...[
        if (raw is Map) ...[
          if (raw['landType'] != null)
            _buildGiInfoCard('Land Type', raw['landType'].toString()),
          if (raw['classification'] != null)
            _buildGiInfoCard('Classification of Land Type', raw['classification'].toString()),
          if (raw['metricRate'] != null)
            _buildGiInfoCard('Metric Rate', raw['metricRate'].toString()),
          if (raw['pricePerHectare'] != null)
            _buildGiInfoCard('Price per Hectare', raw['pricePerHectare'].toString()),
        ],
      ],
    ]);
  }

  Widget _buildGiCropSeasonBlock(String title, Map<String, dynamic>? season) {
    if (season == null) return const SizedBox.shrink();
    if (season['ok'] != true) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.fomraSurfaceVar,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.fomraBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            season['error']?.toString() ?? 'No crop data available for this season.',
            style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
          ),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.fomraSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.fomraBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (season['cropName'] != null)
          _buildGiInfoCard('Crop Name', season['cropName'].toString()),
        if (season['classification'] != null)
          _buildGiInfoCard('Classification', season['classification'].toString()),
        if (season['cropArea'] != null)
          _buildGiInfoCard('Crop Area', season['cropArea'].toString()),
        if (season['landArea'] != null)
          _buildGiInfoCard('Land Area', season['landArea'].toString()),
        if (season['cropCount'] != null)
          _buildGiInfoCard('Crop Count', season['cropCount'].toString()),
        if (season['govtPriority'] != null)
          _buildGiInfoCard('Govt Priority', season['govtPriority'].toString()),
      ]),
    );
  }

  Widget _buildGiCropSeasonTab(String id, String label, Map<String, dynamic>? season) {
    final selected = _selectedCropSeason == id;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF2E7D32).withValues(alpha: 0.14) : Colors.white,
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        child: InkWell(
          onTap: () => setState(() => _selectedCropSeason = id),
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppColors.radiusSm),
              border: Border.all(
                color: selected ? const Color(0xFF2E7D32) : const Color(0xFF2E7D32).withValues(alpha: 0.4),
                width: selected ? 2 : 1,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected ? const Color(0xFF2E7D32) : const Color(0xFF2E7D32).withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGiCropDetail() {
    if (_loadingCrop) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    if (_cropError != null) {
      return Text(_cropError!, style: TextStyle(fontSize: 11, color: Colors.orange.shade900));
    }
    if (_cropData == null) return const SizedBox.shrink();

    final seasons = (_cropData!['seasons'] as Map?)?.cast<String, dynamic>() ?? {};
    final rabi = (seasons['rabi'] as Map?)?.cast<String, dynamic>();
    final kharif = (seasons['kharif'] as Map?)?.cast<String, dynamic>();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        _cropData!['title']?.toString() ?? 'Crop Information',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _buildGiCropSeasonTab('rabi', 'RABI', rabi),
          const SizedBox(width: 8),
          _buildGiCropSeasonTab('kharif', 'KHARIF', kharif),
        ],
      ),
      if (_selectedCropSeason != null) ...[
        const SizedBox(height: 12),
        _buildGiCropSeasonBlock(
          _selectedCropSeason == 'rabi' ? 'RABI' : 'KHARIF',
          _selectedCropSeason == 'rabi' ? rabi : kharif,
        ),
      ],
    ]);
  }

  Widget _buildGiSubdivisionPreview(_TngisSubdivisionRow row) {
    const color = Color(0xFF1B5E20);
    final bundle = _subdivBundles[row.key] ??= _SubdivDocBundle();
    final patta = bundle.documents?['patta'] as Map<String, dynamic>?;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.fomraSurface,
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        border: Border.all(
          color: row.containsPoint
              ? (context.isDarkMode
                      ? AppColors.primaryLight
                      : const Color(0xFF1565C0))
                  .withValues(alpha: 0.5)
              : color.withValues(alpha: 0.25),
          width: row.containsPoint ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (row.containsPoint)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Selected plot',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.isDarkMode
                        ? AppColors.primaryLight
                        : const Color(0xFF1565C0))),
          ),
        _kv(_surveyLabel, row.surveyNumber),
        _kv(_subLabel, row.subLabel),
        if (row.fields['Patta Number']?.isNotEmpty == true)
          _kv('Patta Number', row.fields['Patta Number']!),
        const SizedBox(height: 8),
        if (bundle.loadingPatta)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        else if (_pattaError != null && row.containsPoint)
          Text(_pattaError!, style: TextStyle(fontSize: 11, color: Colors.orange.shade900))
        else if (_hasPattaPdf(patta))
          _buildPattaDocPreview(patta, title: 'Patta / Chitta', pdfOnly: true)
        else
          _buildGiNoResult(),
      ]),
    );
  }

  // â”€â”€ EC UI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // â”€â”€ Shared UI helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 120,
            child: Text(key,
                style: TextStyle(fontSize: 11, color: context.fomraTextSecondary)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 11,
                    color: context.fomraTextPrimary,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  // â”€â”€ Static district fallback â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static const _kStaticDistricts = [
    _Option('001', 'Ariyalur'),       _Option('002', 'Chengalpattu'),
    _Option('003', 'Chennai'),        _Option('004', 'Coimbatore'),
    _Option('005', 'Cuddalore'),      _Option('006', 'Dharmapuri'),
    _Option('007', 'Dindigul'),       _Option('008', 'Erode'),
    _Option('009', 'Kallakurichi'),   _Option('010', 'Kancheepuram'),
    _Option('011', 'Kanniyakumari'), _Option('012', 'Karur'),
    _Option('013', 'Krishnagiri'),    _Option('014', 'Madurai'),
    _Option('015', 'Mayiladuthurai'),_Option('016', 'Nagapattinam'),
    _Option('017', 'Namakkal'),       _Option('018', 'Nilgiris'),
    _Option('019', 'Perambalur'),     _Option('020', 'Pudukkottai'),
    _Option('021', 'Ramanathapuram'),_Option('022', 'Ranipet'),
    _Option('023', 'Salem'),          _Option('024', 'Sivagangai'),
    _Option('025', 'Tenkasi'),        _Option('026', 'Thanjavur'),
    _Option('027', 'Theni'),          _Option('028', 'Thoothukudi'),
    _Option('029', 'Tiruchirappalli'),_Option('030', 'Tirunelveli'),
    _Option('031', 'Tirupathur'),     _Option('032', 'Tiruppur'),
    _Option('033', 'Tiruvallur'),     _Option('034', 'Tiruvannamalai'),
    _Option('035', 'Tiruvarur'),      _Option('036', 'Vellore'),
    _Option('037', 'Viluppuram'),     _Option('038', 'Virudhunagar'),
  ];
}

