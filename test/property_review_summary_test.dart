import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/models/land_lead.dart';
import 'package:fomra_ls/models/lead_review.dart';
import 'package:fomra_ls/services/lead_review_service.dart';
import 'package:fomra_ls/widgets/property_review_summary.dart';

LandLead _lead(String id, {LeadStatus status = LeadStatus.negotiation}) =>
    LandLead(
      leadId: id,
      inputSource: InputSource.broker,
      location: '',
      gpsCoordinates: '',
      village: '',
      taluk: '',
      district: '',
      pincode: '',
      surveyNumber: '',
      landExtent: '',
      ownerName: '',
      contactDetails: '',
      landType: LandType.other,
      roadWidth: '',
      accessDetails: '',
      notes: '',
      addedOn: DateTime(2026, 1, 1),
      status: status,
    );

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + offset);
}

/// Count shown in the tile labelled [label].
String _count(WidgetTester t, String label) {
  final tile = find.ancestor(
    of: find.text(label),
    matching: find.byType(InkWell),
  );
  final texts = t
      .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
      .map((w) => w.data)
      .where((d) => d != label);
  return texts.single!;
}

void main() {
  testWidgets('counts active properties per review status', (t) async {
    LeadReviewIndex.instance.debugSeed([
      // Overdue: next review was yesterday.
      LeadReview(
          id: '1',
          leadId: 'A',
          reviewedAt: _day(-20),
          nextReviewDate: _day(-1)),
      // Due today.
      LeadReview(
          id: '2', leadId: 'B', reviewedAt: _day(-10), nextReviewDate: _day(0)),
      // Overdue too, but the property is Dropped — must not be counted.
      LeadReview(
          id: '3',
          leadId: 'D',
          reviewedAt: _day(-20),
          nextReviewDate: _day(-3)),
    ]);
    final leads = [
      _lead('A'),
      _lead('B'),
      _lead('C'), // never reviewed
      _lead('D', status: LeadStatus.dropped),
    ];

    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: PropertyReviewSummary(leads: leads)),
    ));
    await t.pump();

    expect(_count(t, 'Overdue'), '1');
    expect(_count(t, 'Due today'), '1');
    // Today counts as "this week" as well.
    expect(_count(t, 'Due this week'), '1');
    expect(_count(t, 'Not reviewed'), '1');
  });
}
