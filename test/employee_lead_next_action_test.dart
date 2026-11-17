import 'package:flutter_test/flutter_test.dart';

import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/models/land_lead_meeting.dart';
import 'package:fomra_ls/models/land_lead_site_visit.dart';
import 'package:fomra_ls/utils/employee_lead_next_action.dart';

final _now = DateTime(2026, 7, 16);

LandLead _lead({LeadStatus status = LeadStatus.negotiation}) => LandLead(
      leadId: '12',
      inputSource: InputSource.broker,
      location: 'Ayanavaram',
      gpsCoordinates: '13.09,80.23',
      village: 'V',
      taluk: 'T',
      district: 'D',
      pincode: '600023',
      surveyNumber: '101/2',
      landExtent: '2',
      ownerName: 'Owner',
      contactDetails: '9000000000',
      landType: LandType.residential,
      roadWidth: '20',
      accessDetails: '',
      notes: '',
      addedOn: DateTime(2026, 7, 1),
      status: status,
    );

List<LandLeadMeeting> _meetings() => [
      LandLeadMeeting(
        id: 'm1',
        leadId: '12',
        metAt: DateTime(2026, 7, 3),
        duration: '30',
        notes: '',
        loggedByName: 'Exec',
        createdAt: DateTime(2026, 7, 3),
      ),
    ];

List<LandLeadSiteVisit> _visits(
  LandLeadSiteVisitType type, {
  SiteVisitApprovalStatus status = SiteVisitApprovalStatus.approved,
}) =>
    [
      LandLeadSiteVisit(
        id: 'v-${type.name}',
        leadId: '12',
        visitedAt: DateTime(2026, 7, 4),
        loggedByName: 'Exec',
        visitType: type,
        approvalStatus: status,
        createdAt: DateTime(2026, 7, 4),
      ),
    ];

EmployeeNextAction _action({
  LeadStatus status = LeadStatus.negotiation,
  List<LandLeadMeeting> meetings = const [],
  List<LandLeadSiteVisit> visits = const [],
  int legalDocCount = 0,
}) =>
    EmployeeLeadWorkflow.build(
      lead: _lead(status: status),
      siteVisits: visits,
      meetings: meetings,
      legalDocCount: legalDocCount,
      now: _now,
    ).nextAction;

void main() {
  group('the highest-priority pending activity wins', () {
    test('a lead with nothing done needs the land owner meeting first', () {
      final action = _action();
      expect(action.kind, EmployeeNextActionKind.landOwnerMeeting);
      expect(action.title, 'Conduct Land Owner Meeting');
    });

    test('once the meeting is logged, the site visit is next', () {
      final action = _action(meetings: _meetings());
      expect(action.kind, EmployeeNextActionKind.siteVisit);
      expect(action.title, 'Conduct Site Visit');
    });

    test('once the site visit is logged, legal verification is next', () {
      final action = _action(
        meetings: _meetings(),
        visits: _visits(LandLeadSiteVisitType.employee),
      );
      expect(action.kind, EmployeeNextActionKind.legalVerification);
      expect(action.title, 'Complete Legal Verification');
    });

    test('once legal docs are in, the management site visit is next', () {
      final action = _action(
        meetings: _meetings(),
        visits: _visits(LandLeadSiteVisitType.employee),
        legalDocCount: 2,
      );
      expect(action.kind, EmployeeNextActionKind.managementSiteVisit);
      expect(action.title, 'Management Site Visit');
    });

    test('with everything done, signing is next', () {
      final action = _action(
        meetings: _meetings(),
        visits: [
          ..._visits(LandLeadSiteVisitType.employee),
          ..._visits(LandLeadSiteVisitType.management),
        ],
        legalDocCount: 2,
      );
      expect(action.kind, EmployeeNextActionKind.projectSigning);
      expect(action.title, 'Project Signing');
    });

    test('an earlier pending activity outranks a later one', () {
      // Legal docs and both visits are done, but the owner was never met.
      final action = _action(
        visits: [
          ..._visits(LandLeadSiteVisitType.employee),
          ..._visits(LandLeadSiteVisitType.management),
        ],
        legalDocCount: 5,
      );
      expect(action.kind, EmployeeNextActionKind.landOwnerMeeting);
    });
  });

  group('no pending action', () {
    test('a signed project has none', () {
      final action = _action(status: LeadStatus.signed);
      expect(action.kind, EmployeeNextActionKind.none);
      expect(action.title, 'No Pending Action');
      expect(action.isPending, isFalse);
    });

    test('a dropped lead has none, whatever is missing behind it', () {
      final action = _action(status: LeadStatus.dropped);
      expect(action.kind, EmployeeNextActionKind.none);
      expect(action.title, 'No Pending Action');
    });
  });

  group('site visit approval', () {
    test('a visit awaiting approval has already been made', () {
      final action = _action(
        meetings: _meetings(),
        visits: _visits(
          LandLeadSiteVisitType.employee,
          status: SiteVisitApprovalStatus.pending,
        ),
      );
      expect(action.kind, EmployeeNextActionKind.legalVerification);
    });

    test('a rejected visit still needs doing', () {
      final action = _action(
        meetings: _meetings(),
        visits: _visits(
          LandLeadSiteVisitType.employee,
          status: SiteVisitApprovalStatus.rejected,
        ),
      );
      expect(action.kind, EmployeeNextActionKind.siteVisit);
    });

    test('a management visit does not satisfy the employee site visit', () {
      final action = _action(
        meetings: _meetings(),
        visits: _visits(LandLeadSiteVisitType.management),
      );
      expect(action.kind, EmployeeNextActionKind.siteVisit);
    });
  });

  test('every action explains why it is next', () {
    for (final action in [
      _action(),
      _action(meetings: _meetings()),
      _action(status: LeadStatus.signed),
    ]) {
      expect(action.description, isNotEmpty);
    }
  });

  test('the insight carries the stage the card shows', () {
    final insight = EmployeeLeadWorkflow.build(
      lead: _lead(status: LeadStatus.legal),
      siteVisits: const [],
      meetings: const [],
      legalDocCount: 0,
      now: _now,
    );
    expect(insight.stage, LeadStatus.legal);
  });
}
