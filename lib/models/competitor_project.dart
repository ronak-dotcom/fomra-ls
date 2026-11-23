import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

/// What a competitor project sells.
enum CompetitorType {
  layout('layout', 'Plotted layout'),
  villa('villa', 'Villa'),
  apartment('apartment', 'Apartment'),
  land('land', 'Land');

  const CompetitorType(this.key, this.label);
  final String key;
  final String label;

  static CompetitorType from(String? key) =>
      values.firstWhere((t) => t.key == key, orElse: () => layout);
}

/// Where a competitor project is in its life.
enum CompetitorStage {
  upcoming('upcoming', 'Upcoming', AppColors.purple),
  ongoing('ongoing', 'Ongoing', AppColors.primary),
  completed('completed', 'Completed', AppColors.success),
  resale('resale', 'Only resale', AppColors.warning);

  const CompetitorStage(this.key, this.label, this.color);
  final String key;
  final String label;
  final Color color;

  static CompetitorStage from(String? key) =>
      values.firstWhere((s) => s.key == key, orElse: () => ongoing);
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _int(dynamic v) => _num(v)?.round();

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

String _str(dynamic v) => v?.toString() ?? '';

String? _dateOnly(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

/// One phase of a project: when it launched, plots, sold, left, sizes.
class CompetitorPhase {
  final String id;
  final String label;
  final DateTime? launchDate;
  final int? plots;
  final int? sold;
  final int? available;
  final int? minPlotSqft;
  final int? maxPlotSqft;
  final int sort;

  const CompetitorPhase({
    this.id = '',
    this.label = '',
    this.launchDate,
    this.plots,
    this.sold,
    this.available,
    this.minPlotSqft,
    this.maxPlotSqft,
    this.sort = 0,
  });

  factory CompetitorPhase.fromJson(Map<String, dynamic> j) => CompetitorPhase(
        id: _str(j['id']),
        label: _str(j['label']),
        launchDate: _date(j['launch_date']),
        plots: _int(j['plots']),
        sold: _int(j['sold']),
        available: _int(j['available']),
        minPlotSqft: _int(j['min_plot_sqft']),
        maxPlotSqft: _int(j['max_plot_sqft']),
        sort: _int(j['sort']) ?? 0,
      );

  Map<String, dynamic> toRow(String projectId, int sort) => {
        'project_id': projectId,
        'label': label.trim(),
        'launch_date': _dateOnly(launchDate),
        'plots': plots,
        'sold': sold,
        'available': available,
        'min_plot_sqft': minPlotSqft,
        'max_plot_sqft': maxPlotSqft,
        'sort': sort,
      };
}

/// A dated price & sales check (the project's history).
class CompetitorCheck {
  final String id;
  final DateTime checkedAt;
  final String checkedByName;
  final double? preLaunchPrice;
  final double? quotedPrice;
  final double? negotiatedPrice;
  final int? sold;
  final int? available;
  final String notes;

  const CompetitorCheck({
    this.id = '',
    required this.checkedAt,
    this.checkedByName = '',
    this.preLaunchPrice,
    this.quotedPrice,
    this.negotiatedPrice,
    this.sold,
    this.available,
    this.notes = '',
  });

  factory CompetitorCheck.fromJson(Map<String, dynamic> j) => CompetitorCheck(
        id: _str(j['id']),
        checkedAt: _date(j['checked_at']) ?? DateTime.now(),
        checkedByName: _str(j['checked_by_name']),
        preLaunchPrice: _num(j['pre_launch_price']),
        quotedPrice: _num(j['quoted_price']),
        negotiatedPrice: _num(j['negotiated_price']),
        sold: _int(j['sold']),
        available: _int(j['available']),
        notes: _str(j['notes']),
      );
}

/// A photo or document on a project (private storage).
class CompetitorMedia {
  final String id;
  final String kind; // photo | document
  final String storagePath;
  final String fileName;
  final String contentType;
  final String uploadedByName;
  final DateTime createdAt;

  const CompetitorMedia({
    required this.id,
    required this.kind,
    required this.storagePath,
    required this.fileName,
    required this.contentType,
    required this.uploadedByName,
    required this.createdAt,
  });

  bool get isPhoto => kind == 'photo';

  factory CompetitorMedia.fromJson(Map<String, dynamic> j) => CompetitorMedia(
        id: _str(j['id']),
        kind: _str(j['kind']).isEmpty ? 'photo' : _str(j['kind']),
        storagePath: _str(j['storage_path']),
        fileName: _str(j['file_name']),
        contentType: _str(j['content_type']),
        uploadedByName: _str(j['uploaded_by_name']),
        createdAt: _date(j['created_at']) ?? DateTime.now(),
      );
}

/// A nearby developer project, tracked like a lead (code C-001 …). Holds the
/// latest figures; [phases] and the lead links come with it, the check
/// history and media are loaded on the project page.
class CompetitorProject {
  final String id;
  final String code;
  final String name;
  final String builder;
  final CompetitorType type;
  final CompetitorStage stage;
  final String village;
  final String taluk;
  final String district;
  final double? lat;
  final double? lng;
  final String gpsNote;
  final String mapsLink;
  final double? extentAcres;
  final String approvalAuthority;
  final String approvalNo;
  final String reraNo;
  final double? mainRoadFt;
  final int? minPlotSqft;
  final int? maxPlotSqft;
  final double? preLaunchPrice;
  final double? quotedPrice;
  final double? negotiatedPrice;

  /// Extra ₹ per sq ft for a corner / a preferred facing / a main-road plot.
  final double? plcCorner;
  final double? plcFacing;
  final double? plcRoad;
  final double? glv;
  final double? documentationCharges;
  final double? maintenanceCharge;
  final double? corpus;
  final String otherCharges;
  final String salesPerson;
  final String salesPhone;
  final String amenities;
  final DateTime? launchDate;
  final String notes;
  final String ownerName;
  final String ownerEmail;
  final String createdByName;
  final String source; // field | import | portal
  final DateTime? lastCheckedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<CompetitorPhase> phases;

  /// Leads this project was linked to by hand.
  final List<String> linkedLeadIds;

  CompetitorProject({
    this.id = '',
    this.code = '',
    required this.name,
    this.builder = '',
    this.type = CompetitorType.layout,
    this.stage = CompetitorStage.ongoing,
    this.village = '',
    this.taluk = '',
    this.district = '',
    this.lat,
    this.lng,
    this.gpsNote = '',
    this.mapsLink = '',
    this.extentAcres,
    this.approvalAuthority = '',
    this.approvalNo = '',
    this.reraNo = '',
    this.mainRoadFt,
    this.minPlotSqft,
    this.maxPlotSqft,
    this.preLaunchPrice,
    this.quotedPrice,
    this.negotiatedPrice,
    this.plcCorner,
    this.plcFacing,
    this.plcRoad,
    this.glv,
    this.documentationCharges,
    this.maintenanceCharge,
    this.corpus,
    this.otherCharges = '',
    this.salesPerson = '',
    this.salesPhone = '',
    this.amenities = '',
    this.launchDate,
    this.notes = '',
    this.ownerName = '',
    this.ownerEmail = '',
    this.createdByName = '',
    this.source = 'field',
    this.lastCheckedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.phases = const [],
    this.linkedLeadIds = const [],
  })  : createdAt = createdAt ?? _epoch,
        updatedAt = updatedAt ?? _epoch;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Projects are re-checked every 120 days.
  static const recheckDays = 120;

  LatLng? get point =>
      lat != null && lng != null ? LatLng(lat!, lng!) : null;

  /// Total plots across phases (null when no phase has a count).
  int? get totalPlots => _sum((p) => p.plots);
  int? get totalSold => _sum((p) => p.sold);
  int? get totalAvailable => _sum((p) => p.available);

  int? _sum(int? Function(CompetitorPhase) f) {
    final vals = [for (final p in phases) if (f(p) != null) f(p)!];
    return vals.isEmpty ? null : vals.fold<int>(0, (a, b) => a + b);
  }

  /// Smallest / largest plot across the project and its phases.
  int? get minSqft {
    final vals = [
      if (minPlotSqft != null) minPlotSqft!,
      for (final p in phases) if (p.minPlotSqft != null) p.minPlotSqft!,
    ];
    return vals.isEmpty ? null : vals.reduce((a, b) => a < b ? a : b);
  }

  int? get maxSqft {
    final vals = [
      if (maxPlotSqft != null) maxPlotSqft!,
      for (final p in phases) if (p.maxPlotSqft != null) p.maxPlotSqft!,
    ];
    return vals.isEmpty ? null : vals.reduce((a, b) => a > b ? a : b);
  }

  /// The price a buyer actually pays per sq ft: negotiated, else quoted.
  double? get dealPrice => negotiatedPrice ?? quotedPrice;

  /// First launch date (project or earliest phase).
  DateTime? get firstLaunch {
    final dates = [
      if (launchDate != null) launchDate!,
      for (final p in phases) if (p.launchDate != null) p.launchDate!,
    ]..sort();
    return dates.isEmpty ? null : dates.first;
  }

  /// When the next price check is due.
  DateTime? get recheckDue =>
      (lastCheckedAt ?? (createdAt == _epoch ? null : createdAt))
          ?.add(const Duration(days: recheckDays));

  bool recheckIsDue([DateTime? now]) {
    final due = recheckDue;
    if (due == null) return true;
    return !due.isAfter(now ?? DateTime.now());
  }

  /// "Village, Taluk" (whatever is known).
  String get placeLabel => [village, taluk, district]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .take(2)
      .join(', ');

  factory CompetitorProject.fromJson(Map<String, dynamic> j) {
    final phases = [
      for (final p in (j['competitor_phases'] as List? ?? const []))
        CompetitorPhase.fromJson(Map<String, dynamic>.from(p as Map)),
    ]..sort((a, b) => a.sort.compareTo(b.sort));
    final links = [
      for (final l in (j['competitor_lead_links'] as List? ?? const []))
        _str((l as Map)['lead_id']),
    ];
    return CompetitorProject(
      id: _str(j['id']),
      code: _str(j['code']),
      name: _str(j['name']),
      builder: _str(j['builder']),
      type: CompetitorType.from(j['project_type']?.toString()),
      stage: CompetitorStage.from(j['stage']?.toString()),
      village: _str(j['village']),
      taluk: _str(j['taluk']),
      district: _str(j['district']),
      lat: _num(j['lat']),
      lng: _num(j['lng']),
      gpsNote: _str(j['gps_note']),
      mapsLink: _str(j['maps_link']),
      extentAcres: _num(j['extent_acres']),
      approvalAuthority: _str(j['approval_authority']),
      approvalNo: _str(j['approval_no']),
      reraNo: _str(j['rera_no']),
      mainRoadFt: _num(j['main_road_ft']),
      minPlotSqft: _int(j['min_plot_sqft']),
      maxPlotSqft: _int(j['max_plot_sqft']),
      preLaunchPrice: _num(j['pre_launch_price']),
      quotedPrice: _num(j['quoted_price']),
      negotiatedPrice: _num(j['negotiated_price']),
      plcCorner: _num(j['plc_corner']),
      plcFacing: _num(j['plc_facing']),
      plcRoad: _num(j['plc_road']),
      glv: _num(j['glv']),
      documentationCharges: _num(j['documentation_charges']),
      maintenanceCharge: _num(j['maintenance_charge']),
      corpus: _num(j['corpus']),
      otherCharges: _str(j['other_charges']),
      salesPerson: _str(j['sales_person']),
      salesPhone: _str(j['sales_phone']),
      amenities: _str(j['amenities']),
      launchDate: _date(j['launch_date']),
      notes: _str(j['notes']),
      ownerName: _str(j['owner_name']),
      ownerEmail: _str(j['owner_email']),
      createdByName: _str(j['created_by_name']),
      source: _str(j['source']).isEmpty ? 'field' : _str(j['source']),
      lastCheckedAt: _date(j['last_checked_at']),
      createdAt: _date(j['created_at']),
      updatedAt: _date(j['updated_at']),
      phases: phases,
      linkedLeadIds: links,
    );
  }

  /// The project's own row (no id / code / timestamps; phases separately).
  Map<String, dynamic> toRow() => {
        'name': name.trim(),
        'builder': builder.trim(),
        'project_type': type.key,
        'stage': stage.key,
        'village': village.trim(),
        'taluk': taluk.trim(),
        'district': district.trim(),
        'lat': lat,
        'lng': lng,
        'gps_note': gpsNote.trim(),
        'maps_link': mapsLink.trim(),
        'extent_acres': extentAcres,
        'approval_authority': approvalAuthority.trim(),
        'approval_no': approvalNo.trim(),
        'rera_no': reraNo.trim(),
        'main_road_ft': mainRoadFt,
        'min_plot_sqft': minPlotSqft,
        'max_plot_sqft': maxPlotSqft,
        'pre_launch_price': preLaunchPrice,
        'quoted_price': quotedPrice,
        'negotiated_price': negotiatedPrice,
        'plc_corner': plcCorner,
        'plc_facing': plcFacing,
        'plc_road': plcRoad,
        'glv': glv,
        'documentation_charges': documentationCharges,
        'maintenance_charge': maintenanceCharge,
        'corpus': corpus,
        'other_charges': otherCharges.trim(),
        'sales_person': salesPerson.trim(),
        'sales_phone': salesPhone.trim(),
        'amenities': amenities.trim(),
        'launch_date': _dateOnly(launchDate),
        'notes': notes.trim(),
      };
}
