import 'land_lead.dart';
import '../services/lead_visibility.dart';

enum LeadListFilter {
  totalLeads,
  activeLeads,
  brokerLeads,
  ownerMeetingPending,
  notes,
  siteVisit,
  managementSiteVisit,
  meeting,
  prospect,
  managementMeetingCompleted,
  negotiation,
  legal,
  signed,
  dropped,
}

bool leadHasSiteVisitProgress(LandLead lead) =>
    lead.status == LeadStatus.prospectMeetingCompleted ||
    lead.status == LeadStatus.managementMeetingCompleted ||
    lead.status == LeadStatus.negotiation ||
    lead.status == LeadStatus.legal ||
    lead.status == LeadStatus.signed;

extension LeadListFilterX on LeadListFilter {
  String get title => switch (this) {
        LeadListFilter.totalLeads => 'Total leads',
        LeadListFilter.activeLeads => 'Active leads',
        LeadListFilter.brokerLeads => 'Broker leads',
        LeadListFilter.ownerMeetingPending => 'Owner meeting pending',
        LeadListFilter.notes => 'Notes',
        LeadListFilter.siteVisit => 'Site visit',
        LeadListFilter.managementSiteVisit => 'Management site visit',
        LeadListFilter.meeting => 'Meeting',
        LeadListFilter.prospect => 'Prospect',
        LeadListFilter.managementMeetingCompleted =>
          'Management Meeting Completed',
        LeadListFilter.negotiation => 'Negotiation',
        LeadListFilter.legal => 'Legal',
        LeadListFilter.signed => 'Signed',
        LeadListFilter.dropped => 'Dropped',
      };

  String get subtitle => switch (this) {
        LeadListFilter.totalLeads => 'Every lead in the workspace',
        LeadListFilter.activeLeads => 'Leads still in the pipeline',
        LeadListFilter.brokerLeads => 'Leads sourced through brokers',
        LeadListFilter.ownerMeetingPending =>
          'Land owner meetings still pending',
        LeadListFilter.notes => 'Leads with saved notes',
        LeadListFilter.siteVisit => 'Leads with site visit progress',
        LeadListFilter.managementSiteVisit =>
          'Management-assigned leads with site visit progress',
        LeadListFilter.meeting => 'Prospect meeting stage',
        LeadListFilter.prospect => 'Prospect pipeline leads',
        LeadListFilter.managementMeetingCompleted =>
          'Management meeting completed stage leads',
        LeadListFilter.negotiation => 'Negotiation stage leads',
        LeadListFilter.legal => 'Leads in legal review',
        LeadListFilter.signed => 'Signed leads',
        LeadListFilter.dropped => 'Dropped leads',
      };

  bool matches(LandLead lead) => switch (this) {
        LeadListFilter.totalLeads => true,
        LeadListFilter.activeLeads => lead.status.isActive,
        LeadListFilter.brokerLeads => lead.inputSource == InputSource.broker,
        LeadListFilter.ownerMeetingPending =>
          lead.status == LeadStatus.prospectMeetingPending,
        LeadListFilter.notes => lead.notes.trim().isNotEmpty,
        LeadListFilter.siteVisit => leadHasSiteVisitProgress(lead),
        LeadListFilter.managementSiteVisit =>
          lead.createdByRole == 'management' &&
              leadHasSiteVisitProgress(lead),
        LeadListFilter.meeting => lead.status.isProspect,
        LeadListFilter.prospect => lead.status.isProspect,
        LeadListFilter.managementMeetingCompleted =>
          lead.status == LeadStatus.managementMeetingCompleted,
        LeadListFilter.negotiation => lead.status == LeadStatus.negotiation,
        LeadListFilter.legal => lead.status == LeadStatus.legal,
        LeadListFilter.signed => lead.status == LeadStatus.signed,
        LeadListFilter.dropped => lead.status == LeadStatus.dropped,
      };

  static LeadListFilter? forActionLabel(String label) => switch (label) {
        'Notes' => LeadListFilter.notes,
        'Site visit' => LeadListFilter.siteVisit,
        'Management site visit' => LeadListFilter.managementSiteVisit,
        'Meeting' => LeadListFilter.meeting,
        'Prospect' => LeadListFilter.prospect,
        'Management Meeting Completed' =>
          LeadListFilter.managementMeetingCompleted,
        'Negotiation' => LeadListFilter.negotiation,
        'Legal' => LeadListFilter.legal,
        'Signed' => LeadListFilter.signed,
        'Dropped' => LeadListFilter.dropped,
        _ => null,
      };
}

List<LandLead> leadsVisibleToCurrentUser(List<LandLead> leads) =>
    LeadVisibility.scope(leads);

List<LandLead> filterLeads(List<LandLead> leads, LeadListFilter filter) =>
    leadsVisibleToCurrentUser(leads).where(filter.matches).toList();
