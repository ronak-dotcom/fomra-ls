/// A drop reason, managed by management in Settings (lead_drop_reasons).
/// Hidden reasons ([active] false) are no longer offered when dropping a
/// lead, but leads already dropped for them keep showing them.
class LeadDropReason {
  final String id;
  final String label;
  final bool active;

  const LeadDropReason({
    required this.id,
    required this.label,
    this.active = true,
  });

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'active': active};

  factory LeadDropReason.fromJson(Map<String, dynamic> json) => LeadDropReason(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        active: json['active'] as bool? ?? true,
      );

  LeadDropReason copyWith({String? label, bool? active}) => LeadDropReason(
        id: id,
        label: label ?? this.label,
        active: active ?? this.active,
      );

  @override
  bool operator ==(Object other) =>
      other is LeadDropReason &&
      other.id == id &&
      other.label == label &&
      other.active == active;

  @override
  int get hashCode => Object.hash(id, label, active);
}

const defaultLeadDropReasons = <LeadDropReason>[
  LeadDropReason(
    id: 'owner_related_issues',
    label: 'Owner Related Issues',
  ),
  LeadDropReason(
    id: 'price_budget_mismatch',
    label: 'Price / Budget Mismatch',
  ),
  LeadDropReason(
    id: 'legal_document_issues',
    label: 'Legal & Document Issues',
  ),
  LeadDropReason(
    id: 'location_surrounding_issues',
    label: 'Location & Surrounding Issues',
  ),
  LeadDropReason(
    id: 'land_suitability_issues',
    label: 'Land Suitability Issues',
  ),
  LeadDropReason(
    id: 'negotiation_failed',
    label: 'Negotiation Failed',
  ),
  LeadDropReason(
    id: 'business_management_decision',
    label: 'Business / Management Decision',
  ),
  LeadDropReason(
    id: 'land_owner_meeting_pending_no_response',
    label: 'Land Owner Meeting Pending / No Response',
  ),
];

const _legacyReasonAliases = {
  'ownerRelatedIssues': 'owner_related_issues',
  'priceBudgetMismatch': 'price_budget_mismatch',
  'legalDocumentIssues': 'legal_document_issues',
  'locationSurroundingIssues': 'location_surrounding_issues',
  'landSuitabilityIssues': 'land_suitability_issues',
  'negotiationFailed': 'negotiation_failed',
  'businessManagementDecision': 'business_management_decision',
  'duplicateInvalidNoResponse': 'land_owner_meeting_pending_no_response',
  'other': 'land_owner_meeting_pending_no_response',
  'Duplicate / Invalid / No Response':
      'land_owner_meeting_pending_no_response',
  'Land Owner Meeting Pending / No Response':
      'land_owner_meeting_pending_no_response',
};

String normalizeLeadDropReasonId(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final alias = _legacyReasonAliases[trimmed];
  if (alias != null) return alias;
  return trimmed;
}

LeadDropReason? leadDropReasonFromRaw(
  String? raw, {
  List<LeadDropReason> catalog = defaultLeadDropReasons,
}) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final id = normalizeLeadDropReasonId(trimmed);
  for (final reason in catalog) {
    if (reason.id == id || reason.label == trimmed) return reason;
  }
  for (final reason in defaultLeadDropReasons) {
    if (reason.id == id || reason.label == trimmed) return reason;
  }
  return null;
}
