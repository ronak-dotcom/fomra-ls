import 'package:flutter/foundation.dart';
import '../models/employee_profile.dart';
import '../models/land_lead.dart';
import 'lead_visibility.dart';
import 'view_scope.dart';

class AppStore extends ChangeNotifier {
  static final AppStore instance = AppStore._();

  AppStore._() {
    // Switching between Team and Individual changes what every screen may see,
    // and screens already listen here — so re-notify them off the same signal.
    ViewScope.instance.addListener(notifyListeners);
  }

  final List<LandLead> leads = [];
  final List<EmployeeProfile> employees = [];

  /// Role-scoped leads: Management sees every site; an Executive only sees
  /// the sites (leads) assigned to / created by them; a Reporting Manager /
  /// Head sees their team or just themselves per the header's Team /
  /// Individual toggle. Every screen that lists sites, owners, brokers, tasks,
  /// activities, documents, reports, or map markers should read from this
  /// instead of [leads] directly so access control is enforced consistently
  /// across the whole app. See [LeadVisibility] for the rule itself.
  List<LandLead> get visibleLeads => LeadVisibility.scope(leads);

  /// For the several dialogs (notes, calls, meetings, site visits, legal
  /// docs, signed-project) that are only ever passed a bare leadId, not the
  /// full LandLead — looks up its display name so dialog headers can show
  /// "Kottamedu 2.15 acres" instead of "Lead #47". Searches the raw [leads]
  /// list, not [visibleLeads]: the person already has this exact lead's
  /// dialog open, so scoping would only risk an unnecessary fallback, never
  /// add real protection. Falls back to the bare ID format on a miss,
  /// matching what every call site already showed before this existed.
  String displayNameForLeadId(String leadId) {
    for (final l in leads) {
      if (l.leadId == leadId) return l.displayName;
    }
    return 'Lead #$leadId';
  }

  void addLead(LandLead lead) {
    leads.insert(0, lead);
    notifyListeners();
  }

  void updateLeadStatus(String leadId, LeadStatus status) {
    final idx = leads.indexWhere((l) => l.leadId == leadId);
    if (idx == -1) return;
    leads[idx].status = status;
    notifyListeners();
  }

  void removeLead(String leadId) {
    leads.removeWhere((l) => l.leadId == leadId);
    notifyListeners();
  }

  void updateLeadParcel(String leadId, String surveyNumber, String subDivision) {
    final idx = leads.indexWhere((l) => l.leadId == leadId);
    if (idx == -1) return;
    leads[idx] = leads[idx]
        .copyWith(surveyNumber: surveyNumber, subDivision: subDivision);
    notifyListeners();
  }

  void updateLeadLocation(String leadId, LandLead updated) {
    final idx = leads.indexWhere((l) => l.leadId == leadId);
    if (idx == -1) return;
    leads[idx] = updated;
    notifyListeners();
  }

  void replaceLead(LandLead updated) {
    final idx = leads.indexWhere((l) => l.leadId == updated.leadId);
    if (idx == -1) {
      leads.insert(0, updated);
    } else {
      leads[idx] = updated;
    }
    notifyListeners();
  }

  void setLeads(List<LandLead> newLeads) {
    leads.clear();
    leads.addAll(newLeads);
    notifyListeners();
  }

  void setEmployees(List<EmployeeProfile> list) {
    employees.clear();
    employees.addAll(list);
    notifyListeners();
  }

  void addEmployee(EmployeeProfile profile) {
    employees.insert(0, profile);
    notifyListeners();
  }

  /// Retires an employee from every in-memory list. Anyone who reported to them
  /// is unassigned to match [EmployeeService.deleteEmployee], so the team tree
  /// never points at someone who no longer exists.
  void removeEmployee(String id) {
    final normalized = id.trim().toLowerCase();
    employees.removeWhere((e) => e.id.trim().toLowerCase() == normalized);
    for (var i = 0; i < employees.length; i++) {
      if (employees[i].reportsTo.trim().toLowerCase() == normalized) {
        employees[i] = employees[i].copyWith(reportsTo: '');
      }
    }
    notifyListeners();
  }
}
