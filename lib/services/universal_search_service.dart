import '../models/employee_profile.dart';
import '../models/land_lead.dart';
import '../models/land_lead_legal_document.dart';
import '../utils/contact_directory.dart';
import '../utils/legal_document_catalog.dart';
import '../screens/task_management/task_management_screen.dart';
import '../services/app_store.dart';
import '../services/auth_service.dart';
import '../services/document_index_service.dart';

enum UniversalSearchKind { lead, employee, task, page, contact, document }

class UniversalSearchHit {
  final UniversalSearchKind kind;
  final String title;
  final String subtitle;
  final LandLead? lead;
  final EmployeeProfile? employee;
  final Task? task;
  final String? route;
  final ContactDirectoryKind? contactKind;
  final LandLeadLegalDocument? document;

  const UniversalSearchHit({
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.lead,
    this.employee,
    this.task,
    this.route,
    this.contactKind,
    this.document,
  });
}

class _NavEntry {
  final String label;
  final String? route;
  final ContactDirectoryKind? contactKind;
  final List<String> keywords;

  const _NavEntry({
    required this.label,
    this.route,
    this.contactKind,
    this.keywords = const [],
  });
}

abstract final class UniversalSearchService {
  static const _maxResults = 14;

  static bool _contains(String? value, String q) =>
      value != null && value.trim().isNotEmpty && value.toLowerCase().contains(q);

  /// Lead ID, owner, mobile, village, broker, survey number (+ location extras).
  static bool _leadMatches(LandLead lead, String q) {
    return _contains(lead.leadId, q) ||
        _contains(lead.ownerName, q) ||
        _contains(lead.contactDetails, q) ||
        _contains(lead.brokerName, q) ||
        _contains(lead.brokerContact, q) ||
        _contains(lead.location, q) ||
        _contains(lead.village, q) ||
        _contains(lead.taluk, q) ||
        _contains(lead.district, q) ||
        _contains(lead.pincode, q) ||
        _contains(lead.surveyNumber, q) ||
        _contains(lead.subDivision, q) ||
        _contains(lead.notes, q) ||
        _contains(lead.createdByName, q) ||
        _contains(lead.landType.name, q) ||
        _contains(lead.status.name, q) ||
        _contains(lead.inputSource.name, q);
  }

  static bool _documentMatches(LandLeadLegalDocument doc, String q) {
    final cat = LegalDocumentCatalog.classify(doc.fileName);
    final num = LegalDocumentCatalog.extractDocumentNumber(doc.fileName);
    return _contains(doc.fileName, q) ||
        _contains(doc.leadId, q) ||
        _contains(cat.label, q) ||
        _contains(num, q) ||
        _contains(doc.loggedByName, q);
  }

  static bool _employeeMatches(EmployeeProfile employee, String q) {
    return _contains(employee.fullName, q) ||
        _contains(employee.email, q) ||
        _contains(employee.phone, q) ||
        _contains(employee.designation, q) ||
        _contains(employee.department, q) ||
        _contains(employee.notes, q);
  }

  static bool _taskMatches(Task task, String q) {
    return _contains(task.id, q) ||
        _contains(task.title, q) ||
        _contains(task.description, q) ||
        _contains(task.notes, q) ||
        _contains(task.module, q) ||
        task.assignedTo.any((name) => _contains(name, q));
  }

  static List<_NavEntry> _navEntries(bool isManagement) {
    final entries = <_NavEntry>[
      const _NavEntry(label: 'Home', route: '/home', keywords: ['dashboard', 'portal']),
      const _NavEntry(
        label: 'Land Workspace',
        route: '/land-lead',
        keywords: ['leads', 'workspace', 'land', 'projects'],
      ),
      const _NavEntry(
        label: 'Owner details',
        contactKind: ContactDirectoryKind.owner,
        keywords: ['owners', 'contacts', 'directory'],
      ),
      const _NavEntry(
        label: 'Broker details',
        contactKind: ContactDirectoryKind.broker,
        keywords: ['brokers', 'agents', 'contacts'],
      ),
      const _NavEntry(
        label: 'Change password',
        route: '/change-password',
        keywords: ['security', 'account', 'settings'],
      ),
      const _NavEntry(
        label: 'Settings',
        route: '/settings',
        keywords: [
          'preferences',
          'account',
          'users',
          'dropped reasons',
          'monthly targets',
          'set target',
        ],
      ),
      const _NavEntry(
        label: 'Notifications',
        route: '/notifications',
        keywords: ['alerts', 'bell', 'unread', 'sla', 'approvals'],
      ),
      const _NavEntry(
        label: 'Broker Management',
        route: '/broker-management',
        keywords: ['broker', 'performance', 'conversion', 'success rate'],
      ),
      const _NavEntry(
        label: 'Legal Tracker',
        route: '/legal-tracker',
        keywords: ['ec', 'verification', 'approvals', 'legal'],
      ),
      const _NavEntry(
        label: 'Survey Tracker',
        route: '/survey-tracker',
        keywords: ['survey', 'schedule', 'pending'],
      ),
      const _NavEntry(
        label: 'Owner History',
        route: '/owner-history',
        keywords: ['owner', 'negotiation', 'history'],
      ),
      const _NavEntry(
        label: 'Cost Calculator',
        route: '/cost-calculator',
        keywords: ['cost', 'acre', 'acquisition', 'price'],
      ),
    ];
    if (isManagement) {
      entries.addAll(const [
        _NavEntry(
          label: 'Reports',
          route: '/reports',
          keywords: ['export', 'summary', 'pdf', 'excel'],
        ),
        _NavEntry(
          label: 'Audit Trail',
          route: '/audit-trail',
          keywords: ['logs', 'history', 'changes'],
        ),
        _NavEntry(
          label: 'User management',
          route: '/employee-management',
          keywords: ['employees', 'team', 'staff'],
        ),
      ]);
    }
    return entries;
  }

  static List<UniversalSearchHit> search(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return [];

    final hits = <UniversalSearchHit>[];
    final isManagement = AuthService.instance.isManagement;
    final me = (AuthService.instance.currentUser?.fullName ?? '').trim().toLowerCase();

    for (final lead in AppStore.instance.leads) {
      if (!isManagement &&
          me.isNotEmpty &&
          lead.createdByName.trim().toLowerCase() != me) {
        continue;
      }
      if (!_leadMatches(lead, q)) continue;
      final location = [
        if (lead.village.isNotEmpty) lead.village,
        if (lead.district.isNotEmpty) lead.district,
      ].join(', ');
      hits.add(UniversalSearchHit(
        kind: UniversalSearchKind.lead,
        title: lead.displayName,
        subtitle: [
          if (lead.displayName != 'Lead #${lead.leadId}') '#${lead.leadId}',
          if (location.isNotEmpty) location,
          lead.status.name,
        ].join(' · '),
        lead: lead,
      ));
      if (hits.length >= _maxResults) return hits;
    }

    // Document number / filename hits from cached legal repository.
    for (final doc in DocumentIndexService.instance.documents) {
      if (!_documentMatches(doc, q)) continue;
      if (!isManagement && me.isNotEmpty) {
        final lead = AppStore.instance.leads
            .where((l) => l.leadId == doc.leadId)
            .firstOrNull;
        if (lead == null || lead.createdByName.trim().toLowerCase() != me) {
          continue;
        }
      }
      final cat = LegalDocumentCatalog.classify(doc.fileName);
      final num = LegalDocumentCatalog.extractDocumentNumber(doc.fileName);
      hits.add(UniversalSearchHit(
        kind: UniversalSearchKind.document,
        title: doc.fileName,
        subtitle: [
          cat.label,
          AppStore.instance.displayNameForLeadId(doc.leadId),
          if (num != null) 'Doc #$num',
        ].join(' · '),
        document: doc,
      ));
      if (hits.length >= _maxResults) return hits;
    }

    for (final task in sharedTasks) {
      if (!_taskMatches(task, q)) continue;
      hits.add(UniversalSearchHit(
        kind: UniversalSearchKind.task,
        title: task.title,
        subtitle: [
          task.id,
          if (task.module.isNotEmpty) 'Lead ${task.module}',
          task.status.name,
        ].join(' · '),
        task: task,
      ));
      if (hits.length >= _maxResults) return hits;
    }

    if (isManagement) {
      for (final employee in AppStore.instance.employees) {
        if (!_employeeMatches(employee, q)) continue;
        hits.add(UniversalSearchHit(
          kind: UniversalSearchKind.employee,
          title: employee.fullName,
          subtitle: [
            if (employee.designation.isNotEmpty) employee.designation,
            employee.email,
          ].join(' · '),
          employee: employee,
        ));
        if (hits.length >= _maxResults) return hits;
      }
    }

    for (final entry in _navEntries(isManagement)) {
      final labels = [entry.label, ...entry.keywords];
      if (!labels.any((label) => label.toLowerCase().contains(q))) continue;
      hits.add(UniversalSearchHit(
        kind: entry.contactKind != null
            ? UniversalSearchKind.contact
            : UniversalSearchKind.page,
        title: entry.label,
        subtitle: entry.route != null ? 'Open page' : 'Open directory',
        route: entry.route,
        contactKind: entry.contactKind,
      ));
      if (hits.length >= _maxResults) return hits;
    }

    return hits;
  }

  /// Warm the document index in the background (non-blocking).
  static Future<void> warmDocumentIndex() =>
      DocumentIndexService.instance.ensureLoaded();
}
