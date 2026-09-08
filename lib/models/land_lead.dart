import 'package:flutter/material.dart';

enum InputSource { broker, landowner, referral, internalTeam, existingDatabase }

enum LandType { agricultural, nonAgricultural, residential, commercial, industrial, other }

enum LeadStatus {
  negotiation,
  legal,
  signed,
  dropped,
  prospectMeetingPending,
  prospectMeetingCompleted,
  managementMeetingCompleted,
  onHold,
}

/// Parses status from Supabase, including legacy values saved before the
/// pipeline redesign.
LeadStatus parseLeadStatus(String? raw) {
  final value = raw?.trim() ?? '';
  for (final status in LeadStatus.values) {
    if (status.name == value) return status;
  }
  return switch (value) {
    'new_' => LeadStatus.prospectMeetingPending,
    'contacted' => LeadStatus.prospectMeetingPending,
    'siteVisit' => LeadStatus.prospectMeetingCompleted,
    'closed' => LeadStatus.signed,
    'lost' => LeadStatus.dropped,
    _ => LeadStatus.prospectMeetingPending,
  };
}

/// Extra owner (beyond the primary owner captured in [LandLead.ownerName] /
/// [LandLead.contactDetails]) for sites with multiple land owners.
class OwnerContact {
  final String name;
  final String contact;

  const OwnerContact({required this.name, required this.contact});

  Map<String, dynamic> toJson() => {'name': name, 'contact': contact};

  factory OwnerContact.fromJson(Map<String, dynamic> json) => OwnerContact(
        name: json['name']?.toString() ?? '',
        contact: json['contact']?.toString() ?? '',
      );
}

/// Extra survey number + sub-division (beyond the primary pair captured in
/// [LandLead.surveyNumber] / [LandLead.subDivision]) for sites that span
/// multiple survey plots.
class SurveyEntry {
  final String surveyNumber;
  final String subDivision;

  const SurveyEntry({required this.surveyNumber, this.subDivision = ''});

  Map<String, dynamic> toJson() =>
      {'survey_number': surveyNumber, 'sub_division': subDivision};

  factory SurveyEntry.fromJson(Map<String, dynamic> json) => SurveyEntry(
        surveyNumber: json['survey_number']?.toString() ?? '',
        subDivision: json['sub_division']?.toString() ?? '',
      );
}

class LandLead {
  final String leadId;
  final InputSource inputSource;
  final String location;
  final String gpsCoordinates;
  final String village;
  final String taluk;
  final String district;
  final String pincode;
  final String surveyNumber;
  final String subDivision;
  final List<SurveyEntry> additionalSurveyNumbers;
  final String landExtent;
  final String ownerName;
  final String contactDetails;
  final List<OwnerContact> additionalOwners;
  final String brokerName;
  final String brokerContact;
  /// Name/mobile of the source contact for Landowner, Referral and Internal
  /// Team input sources (Broker keeps using [brokerName]/[brokerContact]).
  final String sourceContactName;
  final String sourceContactNumber;
  final LandType landType;
  /// User-entered land type when [landType] is [LandType.other].
  final String landTypeOther;
  final String roadWidth;
  final String accessDetails;
  final String notes;
  final String sitePhotoUrl;
  final List<String> sitePhotoUrls;
  final DateTime addedOn;
  final String createdByName;
  /// `employee` when the named person posted the lead themselves;
  /// `management` when management created or assigned it.
  final String createdByRole;
  /// Current assignee — who's actually meant to be working this lead right
  /// now. Separate from [createdByName] (who originally sourced/created
  /// it, never changed by reassignment) so the original executive keeps
  /// visibility into their own historical work on a lead after it's
  /// handed to someone else. See LeadVisibility, which checks both.
  final String assignedToName;
  /// Optional custom display name — empty falls back to owner name, then
  /// "Lead #id". The first rename is free; every rename after that needs
  /// management approval (see LandLeadService.renameLead and
  /// land_lead_rename_requests).
  final String leadName;
  final bool leadNameLocked;
  LeadStatus status;
  final String dropReason;
  final String dropNotes;

  // ── Added 2026-08 (Land Sourcing Module Review) ───────────────────────────
  final double? askingPrice;
  final double? expectedPrice;
  final double? guidelineValue;
  final double? marketValueEstimate;

  /// unknown / none / suspected / confirmed / cleared
  final String litigationStatus;
  /// unknown / clear / encumbered / cleared
  final String encumbranceStatus;
  /// unknown / available / not_available
  final String waterAvailability;
  /// unknown / available / not_available
  final String electricityAvailability;
  final String governmentRestrictions;

  /// Co-brokers beyond the primary [brokerName]/[brokerContact] pair.
  final List<OwnerContact> additionalBrokers;

  final double? tokenAdvanceAmount;
  final DateTime? tokenAdvanceDate;
  final String tokenAdvanceNotes;

  /// not_started / drafted / under_review / executed
  final String agreementStatus;
  final DateTime? agreementDate;
  final String agreementNotes;

  final DateTime? reopenedAt;
  final String reopenedByName;
  final String reopenReason;
  final int reopenCount;

  final String? splitFromLeadId;
  final List<String> mergedFromLeadIds;

  final bool isOnHold;
  final String onHoldReason;
  final DateTime? onHoldSince;
  final DateTime? onHoldExpectedResume;
  final LeadStatus? onHoldPreviousStatus;

  /// Set automatically the first time a meeting is logged with an attendee
  /// type of Land Owner or Agreement Holder — survives status changes, so
  /// reports can answer "of leads we actually met the owner for, what
  /// happened to them" regardless of current stage.
  final DateTime? landownerMeetingCompletedAt;

  final String numOwners;
  final String ownerOccupation;
  /// unknown / poor / average / good
  final String locationRating;
  final bool? brokerKnowsOwner;
  final bool? managementMetOwner;
  final String ownerMeetingLocation;

  LandLead({
    required this.leadId,
    required this.inputSource,
    required this.location,
    required this.gpsCoordinates,
    required this.village,
    required this.taluk,
    required this.district,
    required this.pincode,
    required this.surveyNumber,
    this.subDivision = '',
    this.additionalSurveyNumbers = const [],
    required this.landExtent,
    required this.ownerName,
    required this.contactDetails,
    this.additionalOwners = const [],
    this.brokerName = '',
    this.brokerContact = '',
    this.sourceContactName = '',
    this.sourceContactNumber = '',
    required this.landType,
    this.landTypeOther = '',
    required this.roadWidth,
    required this.accessDetails,
    required this.notes,
    this.sitePhotoUrl = '',
    this.sitePhotoUrls = const [],
    required this.addedOn,
    this.createdByName = '',
    this.createdByRole = '',
    this.assignedToName = '',
    this.leadName = '',
    this.leadNameLocked = false,
    this.status = LeadStatus.prospectMeetingPending,
    this.dropReason = '',
    this.dropNotes = '',
    this.askingPrice,
    this.expectedPrice,
    this.guidelineValue,
    this.marketValueEstimate,
    this.litigationStatus = 'unknown',
    this.encumbranceStatus = 'unknown',
    this.waterAvailability = 'unknown',
    this.electricityAvailability = 'unknown',
    this.governmentRestrictions = '',
    this.additionalBrokers = const [],
    this.tokenAdvanceAmount,
    this.tokenAdvanceDate,
    this.tokenAdvanceNotes = '',
    this.agreementStatus = 'not_started',
    this.agreementDate,
    this.agreementNotes = '',
    this.reopenedAt,
    this.reopenedByName = '',
    this.reopenReason = '',
    this.reopenCount = 0,
    this.splitFromLeadId,
    this.mergedFromLeadIds = const [],
    this.isOnHold = false,
    this.onHoldReason = '',
    this.onHoldSince,
    this.onHoldExpectedResume,
    this.onHoldPreviousStatus,
    this.landownerMeetingCompletedAt,
    this.numOwners = '',
    this.ownerOccupation = '',
    this.locationRating = 'unknown',
    this.brokerKnowsOwner,
    this.managementMetOwner,
    this.ownerMeetingLocation = '',
  });

  /// Chip / summary label: employee-posted leads use "Posted by".
  String get ownershipLabel =>
      createdByRole == 'employee' ? 'Posted by' : 'Assigned';

  LandLead copyWith({
    InputSource? inputSource,
    String? location,
    String? gpsCoordinates,
    String? village,
    String? taluk,
    String? district,
    String? pincode,
    String? surveyNumber,
    String? subDivision,
    List<SurveyEntry>? additionalSurveyNumbers,
    String? landExtent,
    String? ownerName,
    String? contactDetails,
    List<OwnerContact>? additionalOwners,
    String? brokerName,
    String? brokerContact,
    String? sourceContactName,
    String? sourceContactNumber,
    LandType? landType,
    String? landTypeOther,
    String? roadWidth,
    String? accessDetails,
    String? notes,
    String? sitePhotoUrl,
    List<String>? sitePhotoUrls,
    String? createdByName,
    String? createdByRole,
    String? assignedToName,
    String? leadName,
    bool? leadNameLocked,
    LeadStatus? status,
    String? dropReason,
    String? dropNotes,
    double? askingPrice,
    double? expectedPrice,
    double? guidelineValue,
    double? marketValueEstimate,
    String? litigationStatus,
    String? encumbranceStatus,
    String? waterAvailability,
    String? electricityAvailability,
    String? governmentRestrictions,
    List<OwnerContact>? additionalBrokers,
    double? tokenAdvanceAmount,
    DateTime? tokenAdvanceDate,
    String? tokenAdvanceNotes,
    String? agreementStatus,
    DateTime? agreementDate,
    String? agreementNotes,
    DateTime? reopenedAt,
    String? reopenedByName,
    String? reopenReason,
    int? reopenCount,
    String? splitFromLeadId,
    List<String>? mergedFromLeadIds,
    bool? isOnHold,
    String? onHoldReason,
    DateTime? onHoldSince,
    DateTime? onHoldExpectedResume,
    LeadStatus? onHoldPreviousStatus,
    DateTime? landownerMeetingCompletedAt,
    String? numOwners,
    String? ownerOccupation,
    String? locationRating,
    bool? brokerKnowsOwner,
    bool? managementMetOwner,
    String? ownerMeetingLocation,
  }) =>
      LandLead(
        leadId: leadId,
        inputSource: inputSource ?? this.inputSource,
        location: location ?? this.location,
        gpsCoordinates: gpsCoordinates ?? this.gpsCoordinates,
        village: village ?? this.village,
        taluk: taluk ?? this.taluk,
        district: district ?? this.district,
        pincode: pincode ?? this.pincode,
        surveyNumber: surveyNumber ?? this.surveyNumber,
        subDivision: subDivision ?? this.subDivision,
        additionalSurveyNumbers:
            additionalSurveyNumbers ?? this.additionalSurveyNumbers,
        landExtent: landExtent ?? this.landExtent,
        ownerName: ownerName ?? this.ownerName,
        contactDetails: contactDetails ?? this.contactDetails,
        additionalOwners: additionalOwners ?? this.additionalOwners,
        brokerName: brokerName ?? this.brokerName,
        brokerContact: brokerContact ?? this.brokerContact,
        sourceContactName: sourceContactName ?? this.sourceContactName,
        sourceContactNumber: sourceContactNumber ?? this.sourceContactNumber,
        landType: landType ?? this.landType,
        landTypeOther: landTypeOther ?? this.landTypeOther,
        roadWidth: roadWidth ?? this.roadWidth,
        accessDetails: accessDetails ?? this.accessDetails,
        notes: notes ?? this.notes,
        sitePhotoUrl: sitePhotoUrl ?? this.sitePhotoUrl,
        sitePhotoUrls: sitePhotoUrls ?? this.sitePhotoUrls,
        addedOn: addedOn,
        createdByName: createdByName ?? this.createdByName,
        createdByRole: createdByRole ?? this.createdByRole,
        assignedToName: assignedToName ?? this.assignedToName,
        leadName: leadName ?? this.leadName,
        leadNameLocked: leadNameLocked ?? this.leadNameLocked,
        status: status ?? this.status,
        dropReason: dropReason ?? this.dropReason,
        dropNotes: dropNotes ?? this.dropNotes,
        askingPrice: askingPrice ?? this.askingPrice,
        expectedPrice: expectedPrice ?? this.expectedPrice,
        guidelineValue: guidelineValue ?? this.guidelineValue,
        marketValueEstimate: marketValueEstimate ?? this.marketValueEstimate,
        litigationStatus: litigationStatus ?? this.litigationStatus,
        encumbranceStatus: encumbranceStatus ?? this.encumbranceStatus,
        waterAvailability: waterAvailability ?? this.waterAvailability,
        electricityAvailability:
            electricityAvailability ?? this.electricityAvailability,
        governmentRestrictions:
            governmentRestrictions ?? this.governmentRestrictions,
        additionalBrokers: additionalBrokers ?? this.additionalBrokers,
        tokenAdvanceAmount: tokenAdvanceAmount ?? this.tokenAdvanceAmount,
        tokenAdvanceDate: tokenAdvanceDate ?? this.tokenAdvanceDate,
        tokenAdvanceNotes: tokenAdvanceNotes ?? this.tokenAdvanceNotes,
        agreementStatus: agreementStatus ?? this.agreementStatus,
        agreementDate: agreementDate ?? this.agreementDate,
        agreementNotes: agreementNotes ?? this.agreementNotes,
        reopenedAt: reopenedAt ?? this.reopenedAt,
        reopenedByName: reopenedByName ?? this.reopenedByName,
        reopenReason: reopenReason ?? this.reopenReason,
        reopenCount: reopenCount ?? this.reopenCount,
        splitFromLeadId: splitFromLeadId ?? this.splitFromLeadId,
        mergedFromLeadIds: mergedFromLeadIds ?? this.mergedFromLeadIds,
        isOnHold: isOnHold ?? this.isOnHold,
        onHoldReason: onHoldReason ?? this.onHoldReason,
        onHoldSince: onHoldSince ?? this.onHoldSince,
        onHoldExpectedResume:
            onHoldExpectedResume ?? this.onHoldExpectedResume,
        onHoldPreviousStatus: onHoldPreviousStatus ?? this.onHoldPreviousStatus,
        landownerMeetingCompletedAt:
            landownerMeetingCompletedAt ?? this.landownerMeetingCompletedAt,
        numOwners: numOwners ?? this.numOwners,
        ownerOccupation: ownerOccupation ?? this.ownerOccupation,
        locationRating: locationRating ?? this.locationRating,
        brokerKnowsOwner: brokerKnowsOwner ?? this.brokerKnowsOwner,
        managementMetOwner: managementMetOwner ?? this.managementMetOwner,
        ownerMeetingLocation: ownerMeetingLocation ?? this.ownerMeetingLocation,
      );
}

extension InputSourceLabel on InputSource {
  String get label => switch (this) {
        InputSource.broker => 'Broker',
        InputSource.landowner => 'Landowner',
        InputSource.referral => 'Referral',
        InputSource.internalTeam => 'Internal Team',
        InputSource.existingDatabase => 'Existing Database',
      };
}

extension LandTypeLabel on LandType {
  String get label => switch (this) {
        LandType.agricultural => 'Agricultural',
        LandType.nonAgricultural => 'Non-Agricultural',
        LandType.residential => 'Residential',
        LandType.commercial => 'Commercial',
        LandType.industrial => 'Industrial',
        LandType.other => 'Other',
      };
}

extension LeadStatusLabel on LeadStatus {
  String get label => switch (this) {
        LeadStatus.negotiation => 'Negotiation',
        LeadStatus.legal => 'Legal',
        LeadStatus.signed => 'Signed',
        LeadStatus.dropped => 'Dropped',
        LeadStatus.prospectMeetingPending => 'Land owner meeting pending',
        LeadStatus.prospectMeetingCompleted => 'Land owner meeting completed',
        LeadStatus.managementMeetingCompleted =>
          'Management Meeting Completed',
        LeadStatus.onHold => 'On Hold',
      };

  /// Short label for compact chips and KPI cards.
  String get shortLabel => switch (this) {
        LeadStatus.prospectMeetingPending => 'Meeting pending',
        LeadStatus.prospectMeetingCompleted => 'Meeting completed',
        LeadStatus.managementMeetingCompleted => 'Mgmt meeting done',
        _ => label,
      };

  bool get isProspect =>
      this == LeadStatus.prospectMeetingPending ||
      this == LeadStatus.prospectMeetingCompleted;

  bool get isAcquired => this == LeadStatus.signed;

  bool get isDropped => this == LeadStatus.dropped;

  bool get isOnHold => this == LeadStatus.onHold;

  /// Signed and Dropped are terminal: once finally approved into one of these,
  /// the lead's stage is locked and can no longer change.
  bool get isTerminal =>
      this == LeadStatus.signed || this == LeadStatus.dropped;

  /// On Hold is deliberately excluded here — paused, not actively worked,
  /// but not lost either. It still shows up under "Total leads" and any
  /// explicit On Hold filter, just not in "active negotiation" counts.
  bool get isActive => !isAcquired && !isDropped && !isOnHold;
}

/// Display order for Stage & Status dropdowns and filter chips.
const leadStatusPipelineOrder = <LeadStatus>[
  LeadStatus.prospectMeetingPending,
  LeadStatus.prospectMeetingCompleted,
  LeadStatus.managementMeetingCompleted,
  LeadStatus.negotiation,
  LeadStatus.legal,
  LeadStatus.signed,
  LeadStatus.onHold,
  LeadStatus.dropped,
];

extension LeadStatusColor on LeadStatus {
  Color get color => switch (this) {
        LeadStatus.negotiation => const Color(0xFFEA580C),
        LeadStatus.legal => const Color(0xFF7C3AED),
        LeadStatus.signed => const Color(0xFF16A34A),
        LeadStatus.dropped => const Color(0xFFDC2626),
        LeadStatus.prospectMeetingPending => const Color(0xFFDB2777),
        LeadStatus.prospectMeetingCompleted => const Color(0xFF0891B2),
        LeadStatus.managementMeetingCompleted => const Color(0xFF4F46E5),
        LeadStatus.onHold => const Color(0xFF64748B),
      };
}

/// The one place a lead's display name/title is computed, so every screen —
/// Lead Detail, the leads list, search results, reports, map popups,
/// notifications — shows exactly the same name for the same lead. Prefers
/// the custom name once set (see LandLeadRenameService), falling back to
/// the owner's name, falling back to the bare lead number.
extension LandLeadDisplayName on LandLead {
  String get displayName => leadName.trim().isNotEmpty
      ? leadName.trim()
      : ownerName.trim().isEmpty
          ? 'Lead #$leadId'
          : ownerName.trim();

  /// Whether this lead's location came from a verified live GPS capture
  /// (GpsVerificationService.captureLive — rejects mock locations and
  /// readings below its accuracy threshold) rather than a typed/manually
  /// picked coordinate. Storage format is GpsFix.toStorage()'s
  /// 'LIVE|<lat>|<lng>|<accuracy>|<timestamp>' — see lib/models/gps_fix.dart.
  ///
  /// Being physically present with a verified GPS fix at the moment a lead
  /// is created is itself proof of a site visit, distinct from (and not a
  /// substitute for) a later logged revisit in land_lead_site_visits.
  bool get isLiveGpsVerified => gpsCoordinates.trim().startsWith('LIVE|');
}
