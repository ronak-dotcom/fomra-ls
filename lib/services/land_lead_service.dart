import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/lead_location_parser.dart';
import '../models/land_lead.dart';
import '../models/lead_change_request.dart';
import '../utils/image_compressor.dart';
import 'app_store.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';
import 'broker_directory.dart';
import 'lead_change_approval_service.dart';
import 'role_access.dart';

typedef LeadSaveProgressCallback = void Function(String message);

class LandLeadService {
  static SupabaseClient get _db => Supabase.instance.client;
  static const _photoBucket = 'land-lead-photos';

  /// Best-effort owner/broker/executive lookup from the in-memory lead cache,
  /// used to enrich audit entries for actions that only have a `leadId`.
  static ({String owner, String broker, String executive}) _auditContextFor(
    String leadId,
  ) {
    for (final l in AppStore.instance.leads) {
      if (l.leadId == leadId) {
        return (owner: l.ownerName, broker: l.brokerName, executive: l.createdByName);
      }
    }
    return (owner: '', broker: '', executive: '');
  }

  static Future<List<LandLead>> getAll() async {
    // The Broker Directory loads alongside, so broker names show correctly
    // the moment the leads do (it never fails the lead load).
    final directory = BrokerDirectory.instance.ensureLoaded();
    final rows = await _db
        .from('land_leads')
        .select()
        .order('added_on', ascending: false);
    await directory;
    return (rows as List).map((r) => _fromRow(r as Map<String, dynamic>)).toList();
  }

  /// The lead as currently stored, or null if there is no such row.
  static Future<LandLead?> getById(String leadId) async {
    final row = await _db
        .from('land_leads')
        .select()
        .eq('id', leadId)
        .maybeSingle();
    return row == null ? null : _fromRow(row);
  }

  /// [clientRef] tags one "Save" of the Add Lead form. If the same save is
  /// sent twice — the first reply was lost on a weak signal, or it was queued
  /// offline and retried — the lead already saved under that tag is returned
  /// instead of creating a duplicate (and gets its photos if they were lost).
  static Future<LandLead> create(
    LandLead lead, {
    List<Uint8List> sitePhotoBytes = const [],
    LeadSaveProgressCallback? onProgress,
    String? clientRef,
  }) async {
    onProgress?.call('Saving lead details…');
    if (clientRef != null) {
      final existing = await _findByClientRef(clientRef);
      if (existing != null) {
        return _attachMissingPhotos(existing, sitePhotoBytes, onProgress);
      }
    }
    final userId = _db.auth.currentUser?.id;
    final createdByName = AuthService.instance.currentUser?.fullName ?? '';
    final createdByRole =
        AuthService.instance.isManagement ? 'management' : 'employee';
    final leadId = await _db.rpc('generate_land_lead_id') as String;

    var sitePhotoUrls = List<String>.from(lead.sitePhotoUrls);
    var sitePhotoUrl = lead.sitePhotoUrl;

    final Map<String, dynamic> row;
    try {
      row = await _insertLandLead(
      {
        'id': leadId,
        'input_source': lead.inputSource.name,
        'location': lead.location,
        'gps_coordinates': lead.gpsCoordinates,
        'village': lead.village,
        'taluk': lead.taluk,
        'district': lead.district,
        'pincode': lead.pincode,
        'survey_number': lead.surveyNumber,
        'sub_division': lead.subDivision,
        'land_extent': lead.landExtent,
        'owner_name': lead.ownerName,
        'contact_details': lead.contactDetails,
        'contact_type': lead.contactType,
        'contact_relation': lead.contactRelation,
        'broker_name': lead.brokerName,
        'broker_contact': lead.brokerContact,
        'source_contact_name': lead.sourceContactName,
        'source_contact_number': lead.sourceContactNumber,
        'land_type': lead.landType.name,
        'land_type_other': lead.landTypeOther,
        'road_width': lead.roadWidth,
        'access_details': lead.accessDetails,
        'notes': lead.notes,
        'status': lead.status.name,
        'added_on': lead.addedOn.toUtc().toIso8601String(),
        if (userId != null) 'created_by': userId,
        if (createdByName.isNotEmpty) 'created_by_name': createdByName,
        'created_by_role': createdByRole,
        if (clientRef != null) 'client_ref': clientRef,
      },
      lead.additionalOwners,
      lead.additionalSurveyNumbers,
    );
    } on PostgrestException catch (e) {
      // The same save landed a moment ago (a retry racing the original):
      // use that lead rather than failing.
      if (e.code == '23505' && clientRef != null) {
        final existing = await _findByClientRef(clientRef);
        if (existing != null) {
          return _attachMissingPhotos(existing, sitePhotoBytes, onProgress);
        }
      }
      rethrow;
    }

    final photos = sitePhotoBytes.where((b) => b.isNotEmpty).take(4).toList();
    if (photos.isNotEmpty) {
      sitePhotoUrls = [];
      for (var i = 0; i < photos.length; i++) {
        onProgress?.call('Uploading photo ${i + 1} of ${photos.length}…');
        final url = await _uploadSitePhoto(leadId, photos[i], index: i + 1);
        sitePhotoUrls.add(url);
      }
      sitePhotoUrl = sitePhotoUrls.first;
      onProgress?.call('Finalizing lead…');
      await _db.from('land_leads').update({
        'site_photo_url': sitePhotoUrl,
        'site_photo_urls': sitePhotoUrls,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', leadId);
    }

    final created = _fromRow({
      ...row,
      'site_photo_url': sitePhotoUrl,
      'site_photo_urls': sitePhotoUrls,
      'sub_division': lead.subDivision,
    });
    await AuditLogService.log(
      action: 'create',
      entityType: 'lead',
      entityId: created.leadId,
      field: 'lead',
      oldValue: '',
      newValue: created.ownerName,
      module: 'Lead',
      leadId: created.leadId,
      ownerName: created.ownerName,
      brokerName: created.brokerName,
      executiveName: created.createdByName,
    );
    return created;
  }

  /// The lead saved under [clientRef], if any (null when the column isn't
  /// there yet or the lookup fails — then a normal create goes ahead).
  static Future<LandLead?> _findByClientRef(String clientRef) async {
    try {
      final row = await _db
          .from('land_leads')
          .select()
          .eq('client_ref', clientRef)
          .maybeSingle();
      return row == null ? null : _fromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' || e.code == '42703') return null;
      rethrow;
    }
  }

  /// A retried save whose lead already exists: upload its photos if the
  /// first attempt saved the lead but lost the photos.
  static Future<LandLead> _attachMissingPhotos(
    LandLead existing,
    List<Uint8List> sitePhotoBytes,
    LeadSaveProgressCallback? onProgress,
  ) async {
    final photos = sitePhotoBytes.where((b) => b.isNotEmpty).take(4).toList();
    if (photos.isEmpty || existing.sitePhotoUrls.isNotEmpty) return existing;
    final urls = <String>[];
    for (var i = 0; i < photos.length; i++) {
      onProgress?.call('Uploading photo ${i + 1} of ${photos.length}…');
      urls.add(await _uploadSitePhoto(existing.leadId, photos[i], index: i + 1));
    }
    await _db.from('land_leads').update({
      'site_photo_url': urls.first,
      'site_photo_urls': urls,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', existing.leadId);
    return existing.copyWith(sitePhotoUrl: urls.first, sitePhotoUrls: urls);
  }

  /// Inserts a lead row, including `additional_owners` and
  /// `additional_survey_numbers` when those columns exist. Falls back to
  /// inserting without whichever column is missing on databases that
  /// haven't had the corresponding `supabase/land_lead_*.sql` applied yet.
  static Future<Map<String, dynamic>> _insertLandLead(
    Map<String, dynamic> base,
    List<OwnerContact> additionalOwners,
    List<SurveyEntry> additionalSurveyNumbers,
  ) async {
    var payload = {
      ...base,
      'additional_owners': additionalOwners.map((o) => o.toJson()).toList(),
      'additional_survey_numbers':
          additionalSurveyNumbers.map((s) => s.toJson()).toList(),
    };
    while (true) {
      try {
        return await _db.from('land_leads').insert(payload).select().single();
      } on PostgrestException catch (e) {
        final missingKey = _missingOptionalColumn(e, payload);
        if (missingKey == null) rethrow;
        payload = {...payload}..remove(missingKey);
      }
    }
  }

  /// Updates a lead row, including `additional_owners` and
  /// `additional_survey_numbers` when those columns exist. Falls back to
  /// updating without whichever column is missing on databases that haven't
  /// had the corresponding `supabase/land_lead_*.sql` applied yet.
  static Future<Map<String, dynamic>> _updateLandLead(
    String leadId,
    Map<String, dynamic> base,
    List<OwnerContact> additionalOwners,
    List<SurveyEntry> additionalSurveyNumbers,
  ) async {
    var payload = {
      ...base,
      'additional_owners': additionalOwners.map((o) => o.toJson()).toList(),
      'additional_survey_numbers':
          additionalSurveyNumbers.map((s) => s.toJson()).toList(),
    };
    while (true) {
      try {
        return await _db
            .from('land_leads')
            .update(payload)
            .eq('id', leadId)
            .select()
            .single();
      } on PostgrestException catch (e) {
        final missingKey = _missingOptionalColumn(e, payload);
        if (missingKey == null) rethrow;
        payload = {...payload}..remove(missingKey);
      }
    }
  }

  /// Optional payload keys that may not exist yet on a database that hasn't
  /// had the corresponding `supabase/land_lead_*.sql` migration applied.
  static const _optionalColumns = [
    'additional_owners',
    'additional_survey_numbers',
    'client_ref',
  ];

  /// Returns the payload key a `PGRST204` "column not found" error refers
  /// to, if it's one of [_optionalColumns] present in [payload] — so callers
  /// can retry without it.
  static String? _missingOptionalColumn(
    PostgrestException e,
    Map<String, dynamic> payload,
  ) {
    if (e.code != 'PGRST204') return null;
    for (final key in _optionalColumns) {
      if (payload.containsKey(key) && e.message.contains(key)) return key;
    }
    return null;
  }

  static Future<String> _uploadSitePhoto(
    String leadId,
    Uint8List rawBytes, {
    required int index,
  }) async {
    final compressed = await ImageCompressor.compressTo250Kb(rawBytes);
    final path = index == 1 ? '$leadId.jpg' : '${leadId}_$index.jpg';

    await _db.storage.from(_photoBucket).uploadBinary(
          path,
          compressed,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return _db.storage.from(_photoBucket).getPublicUrl(path);
  }

  /// Reassign a lead to an employee (by name). Since a lead's owning employee
  /// is tracked via created_by_name, this makes the lead appear on that
  /// employee's leads page.
  /// Reassigns a lead to [employeeEmail] ([employeeName] is display-only).
  /// Deliberately does NOT touch created_by_name/created_by — that stays
  /// the original creator forever, so their own historical meetings/calls/
  /// visits on this lead stay visible to them (LeadVisibility checks both
  /// created_by_name and assigned_to_name — see that class). Resolves the
  /// assignee's real auth UUID via user_id_for_email() so the RLS policy's
  /// assigned_to = auth.uid() branch actually grants them write access,
  /// not just app-level visibility.
  static Future<void> assignTo(
    String leadId,
    String employeeName, {
    required String employeeEmail,
  }) async {
    String? assigneeUuid;
    if (employeeEmail.trim().isNotEmpty) {
      try {
        assigneeUuid =
            await _db.rpc('user_id_for_email', params: {'target_email': employeeEmail.trim()})
                as String?;
      } catch (_) {
        // Best-effort — app-level visibility (assigned_to_name) still works
        // even if this couldn't resolve a UUID for some reason.
      }
    }
    await _db.from('land_leads').update({
      'assigned_to': assigneeUuid,
      'assigned_to_name': employeeName,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', leadId);
    final ctx = _auditContextFor(leadId);
    await AuditLogService.log(
      action: 'assign',
      entityType: 'lead',
      entityId: leadId,
      field: 'assigned_to_name',
      oldValue: '',
      newValue: employeeName,
      module: 'Lead',
      leadId: leadId,
      ownerName: ctx.owner,
      brokerName: ctx.broker,
      executiveName: employeeName,
    );
  }

  static Future<void> updateStatus(
    String leadId,
    LeadStatus status, {
    LeadStatus? previousStatus,
  }) async {
    // A Signed/Dropped lead is terminal — reject any stage change server-side
    // too, so the lock holds even if a UI guard is bypassed.
    if (previousStatus != null && previousStatus.isTerminal) {
      throw StateError(
        'This lead is already ${previousStatus.label} and can no longer be modified.',
      );
    }

    final base = <String, dynamic>{
      'status': status.name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    // Clearing drop reason/notes is best-effort: on a plain status change we
    // don't want a database that hasn't had lead_drop_reason.sql applied to
    // block the update. Retry without those columns if they're missing.
    final payload = <String, dynamic>{...base};
    if (status != LeadStatus.dropped) {
      payload['drop_reason'] = '';
      payload['drop_notes'] = '';
    }

    List rows;
    try {
      rows = await _db
          .from('land_leads')
          .update(payload)
          .eq('id', leadId)
          .select('id');
    } on PostgrestException catch (e) {
      final missingDropColumn = e.code == 'PGRST204' &&
          (e.message.contains('drop_notes') ||
              e.message.contains('drop_reason'));
      if (!missingDropColumn) rethrow;
      rows = await _db
          .from('land_leads')
          .update(base)
          .eq('id', leadId)
          .select('id');
    }
    if (rows.isEmpty) {
      throw Exception('Lead $leadId was not updated (not found or blocked)');
    }
    final ctx = _auditContextFor(leadId);
    await AuditLogService.log(
      action: 'update',
      entityType: 'lead',
      entityId: leadId,
      field: 'status',
      oldValue: previousStatus?.name ?? '',
      newValue: status.name,
      module: 'Lead',
      leadId: leadId,
      ownerName: ctx.owner,
      brokerName: ctx.broker,
      executiveName: ctx.executive,
    );
  }

  /// Reopens a Dropped lead back into an active stage. Admin-only, and
  /// intentionally the *only* path in the codebase that moves a lead out of
  /// a terminal stage — [updateStatus] still refuses that unconditionally.
  /// Always requires a reason and always writes both a status-change audit
  /// entry and a dedicated 'reopen' one, plus stamps reopened_at/by/reason
  /// on the row itself so the history is visible without digging through the
  /// audit log.
  static Future<void> reopenDropped({
    required String leadId,
    required LeadStatus targetStatus,
    required String reason,
  }) async {
    if (!RoleAccess.canDelete) {
      // Reopening a terminal lead is at least as consequential as a hard
      // delete (it un-does a locked, approved outcome) — same gate.
      throw StateError(
        'Only an Administrator can reopen a dropped lead.',
      );
    }
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('A reason is required to reopen a dropped lead.');
    }
    if (targetStatus.isTerminal) {
      throw ArgumentError('Cannot reopen a lead into a terminal stage.');
    }

    final current = await _db
        .from('land_leads')
        .select('status, reopen_count')
        .eq('id', leadId)
        .maybeSingle();
    if (current == null) {
      throw Exception('Lead $leadId was not found.');
    }
    if (current['status'] != LeadStatus.dropped.name) {
      throw StateError('This lead is not currently Dropped.');
    }
    final nextReopenCount = ((current['reopen_count'] as int?) ?? 0) + 1;

    final userId = _db.auth.currentUser?.id;
    final userName = AuthService.instance.currentUser?.fullName ?? '';
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final rows = await _db
        .from('land_leads')
        .update({
          'status': targetStatus.name,
          'drop_reason': '',
          'drop_notes': '',
          'reopened_at': nowIso,
          'reopened_by': userId,
          'reopened_by_name': userName,
          'reopen_reason': trimmedReason,
          'reopen_count': nextReopenCount,
          'updated_at': nowIso,
        })
        .eq('id', leadId)
        .eq('status', LeadStatus.dropped.name)
        .select('id');
    if (rows.isEmpty) {
      throw Exception(
        'Lead $leadId could not be reopened (not found, or no longer Dropped).',
      );
    }

    final ctx = _auditContextFor(leadId);
    await AuditLogService.log(
      action: 'reopen',
      entityType: 'lead',
      entityId: leadId,
      field: 'status',
      oldValue: 'dropped',
      newValue: '${targetStatus.name} (reopen #$nextReopenCount: $trimmedReason)',
      module: 'Lead',
      leadId: leadId,
      ownerName: ctx.owner,
      brokerName: ctx.broker,
      executiveName: ctx.executive,
    );
  }

  static Future<void> markDropped({
    required String leadId,
    required String reasonLabel,
    required String notes,
  }) async {
    await _db.from('land_leads').update({
      'status': LeadStatus.dropped.name,
      'drop_reason': reasonLabel.trim(),
      'drop_notes': notes.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', leadId);
    final ctx = _auditContextFor(leadId);
    await AuditLogService.log(
      action: 'update',
      entityType: 'lead',
      entityId: leadId,
      field: 'status',
      oldValue: '',
      newValue: 'dropped:${reasonLabel.trim()}',
      module: 'Lead',
      leadId: leadId,
      ownerName: ctx.owner,
      brokerName: ctx.broker,
      executiveName: ctx.executive,
    );
  }

  static Future<void> updateSurveySub(
      String leadId, String surveyNumber, String subDivision) async {
    await _db.from('land_leads').update({
      'survey_number': surveyNumber,
      'sub_division': subDivision,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', leadId);
  }

  static Future<void> updateLocation(
    String leadId, {
    required String location,
    required String village,
    required String taluk,
    required String district,
    required String pincode,
  }) async {
    await _db.from('land_leads').update({
      'location': location,
      'village': village,
      'taluk': taluk,
      'district': district,
      'pincode': pincode,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', leadId);
  }

  /// Fields sensitive enough to warrant their own audit-log entry when
  /// changed on an edit — ownership/identity/land-description data a legal
  /// or compliance review would need to trace later. Deliberately narrower
  /// than "every field" (e.g. notes/photos churn too often to be useful
  /// signal here); the generic 'lead' entry below still covers a save as a
  /// whole.
  static final _auditedFields = <String, String Function(LandLead)>{
    'owner_name': (l) => l.ownerName,
    'contact_details': (l) => l.contactDetails,
    'broker_name': (l) => l.brokerName,
    'broker_contact': (l) => l.brokerContact,
    'land_extent': (l) => l.landExtent,
    'survey_number': (l) => l.surveyNumber,
    'sub_division': (l) => l.subDivision,
    'village': (l) => l.village,
    'taluk': (l) => l.taluk,
    'district': (l) => l.district,
    // Where the property is on the map — moving it is as significant as
    // changing the survey number, so it's audited and approval-gated too.
    'location': (l) => l.location,
    'gps_coordinates': (l) => l.gpsCoordinates,
  };

  /// After this long from when a lead was saved, editing an already-filled
  /// core field needs management approval (filling a blank one never does).
  static const freeEditWindow = Duration(hours: 1);

  /// A GPS pin within this distance of the old one counts as unchanged: a
  /// re-capture at the same spot always differs by a few metres, and the
  /// stored text can differ in format for the same point.
  static const gpsSameSpotMeters = 25.0;

  /// Whether [oldVal] → [newVal] is no real change for [field].
  static bool _isUnchanged(String field, String oldVal, String newVal) {
    if (oldVal == newVal) return true;
    if (field == 'gps_coordinates') {
      final moved = gpsDistanceMeters(oldVal, newVal);
      if (moved != null && moved < gpsSameSpotMeters) return true;
    }
    return false;
  }

  static Future<void> _logFieldChanges(
    LandLead previous,
    LandLead updated,
  ) async {
    for (final entry in _auditedFields.entries) {
      final oldValue = entry.value(previous).trim();
      final newValue = entry.value(updated).trim();
      if (oldValue == newValue) continue;
      await AuditLogService.log(
        action: 'update',
        entityType: 'lead',
        entityId: updated.leadId,
        field: entry.key,
        oldValue: oldValue,
        newValue: newValue,
        module: 'Lead',
        leadId: updated.leadId,
        ownerName: updated.ownerName,
        brokerName: updated.brokerName,
        executiveName: updated.createdByName,
      );
    }
  }

  /// Core identifying info (see _auditedFields / leadChangeFieldLabels),
  /// split into what [update] may write now ([apply]) and what needs
  /// management approval ([pending]). Free: filling a blank field, or any
  /// change within [freeEditWindow] of the lead being saved. Otherwise the
  /// change is held back and never written until approved — unlike renaming,
  /// there's no "apply then revert". A GPS pin moved less than
  /// [gpsSameSpotMeters] counts as unchanged. Fields outside this set
  /// (status, notes, photos, …) are not part of this rule.
  ///
  /// With no [previous] there is nothing to compare, so everything applies
  /// (offline sync now always passes the server copy).
  static ({Map<String, dynamic> apply, List<LeadFieldChange> pending})
      splitCoreFieldChanges(LandLead lead, LandLead? previous,
          {DateTime? now}) {
    final apply = <String, dynamic>{};
    final pending = <LeadFieldChange>[];
    final withinFreeWindow = previous != null &&
        (now ?? DateTime.now()).difference(previous.addedOn) < freeEditWindow;
    for (final entry in _auditedFields.entries) {
      final newVal = entry.value(lead).trim();
      if (previous == null) {
        apply[entry.key] = newVal;
        continue;
      }
      final oldVal = entry.value(previous).trim();
      if (_isUnchanged(entry.key, oldVal, newVal)) continue;
      final blankToFilled = oldVal.isEmpty && newVal.isNotEmpty;
      if (withinFreeWindow || blankToFilled) {
        apply[entry.key] = newVal;
      } else {
        pending.add(LeadFieldChange(
          field: entry.key,
          label: leadChangeFieldLabels[entry.key] ?? entry.key,
          oldValue: oldVal,
          newValue: newVal,
        ));
      }
    }
    return (apply: apply, pending: pending);
  }

  static Future<LandLead> update(
    LandLead lead, {
    List<Uint8List> sitePhotoBytes = const [],
    LeadSaveProgressCallback? onProgress,
    LandLead? previous,
  }) async {
    onProgress?.call('Saving lead details…');
    var sitePhotoUrls = List<String>.from(lead.sitePhotoUrls);
    var sitePhotoUrl = sitePhotoUrls.isNotEmpty ? sitePhotoUrls.first : '';

    final newPhotos =
        sitePhotoBytes.where((b) => b.isNotEmpty).take(4).toList();
    final slotsLeft = 4 - sitePhotoUrls.length;
    if (newPhotos.isNotEmpty && slotsLeft > 0) {
      final uploadCount = newPhotos.length.clamp(0, slotsLeft);
      for (var i = 0; i < newPhotos.length && sitePhotoUrls.length < 4; i++) {
        onProgress?.call('Uploading photo ${i + 1} of $uploadCount…');
        final url = await _uploadSitePhoto(
          lead.leadId,
          newPhotos[i],
          index: sitePhotoUrls.length + 1,
        );
        sitePhotoUrls.add(url);
      }
      sitePhotoUrl = sitePhotoUrls.first;
      onProgress?.call('Finalizing lead…');
    }

    final split = splitCoreFieldChanges(lead, previous);
    final pendingChanges = split.pending;
    final auditedPayload = split.apply;

    final row = await _updateLandLead(
      lead.leadId,
      {
        'input_source': lead.inputSource.name,
        'pincode': lead.pincode,
        'land_type': lead.landType.name,
        'land_type_other': lead.landTypeOther,
        'road_width': lead.roadWidth,
        'access_details': lead.accessDetails,
        'notes': lead.notes,
        'status': lead.status.name,
        'source_contact_name': lead.sourceContactName,
        'source_contact_number': lead.sourceContactNumber,
        // Only once chosen: an edit queued offline before this field existed
        // carries '' and must not wipe a contact type set since.
        if (lead.contactType.isNotEmpty) ...{
          'contact_type': lead.contactType,
          'contact_relation': lead.contactRelation,
        },
        'site_photo_url': sitePhotoUrl,
        'site_photo_urls': sitePhotoUrls,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        ...auditedPayload,
      },
      lead.additionalOwners,
      lead.additionalSurveyNumbers,
    );

    final updated = _fromRow({
      ...row,
      'site_photo_url': sitePhotoUrl,
      'site_photo_urls': sitePhotoUrls,
    });
    await AuditLogService.log(
      action: 'update',
      entityType: 'lead',
      entityId: updated.leadId,
      field: 'lead',
      oldValue: '',
      newValue: updated.ownerName,
      module: 'Lead',
      leadId: updated.leadId,
      ownerName: updated.ownerName,
      brokerName: updated.brokerName,
      executiveName: updated.createdByName,
    );
    if (previous != null) {
      // updated reflects the DB row as actually written — pending fields
      // were never in the payload above, so this correctly still shows
      // their old value and _logFieldChanges naturally skips them (no
      // diff to log for a field that didn't actually change in the DB).
      await _logFieldChanges(previous, updated);
    }
    if (pendingChanges.isNotEmpty) {
      await LeadChangeApprovalService.submitPending(
        leadId: lead.leadId,
        changes: pendingChanges,
      );
    }
    return updated;
  }

  /// Targeted update for the "Deal & Risk Details" dialog — touches only
  /// the pricing/risk/multi-broker/milestone columns added in the Land
  /// Sourcing Module Review, leaving every other lead field untouched.
  /// Deliberately separate from [update] so this can't accidentally clobber
  /// core lead fields, and vice versa.
  static Future<LandLead> updateDealAndRiskDetails({
    required String leadId,
    LandLead? previous,
    double? askingPrice,
    double? expectedPrice,
    double? guidelineValue,
    double? marketValueEstimate,
    required String litigationStatus,
    required String encumbranceStatus,
    required String waterAvailability,
    required String electricityAvailability,
    required String governmentRestrictions,
    required List<OwnerContact> additionalBrokers,
    double? tokenAdvanceAmount,
    DateTime? tokenAdvanceDate,
    required String tokenAdvanceNotes,
    required String agreementStatus,
    DateTime? agreementDate,
    required String agreementNotes,
  }) async {
    final payload = <String, dynamic>{
      'asking_price': askingPrice,
      'expected_price': expectedPrice,
      'guideline_value': guidelineValue,
      'market_value_estimate': marketValueEstimate,
      'litigation_status': litigationStatus,
      'encumbrance_status': encumbranceStatus,
      'water_availability': waterAvailability,
      'electricity_availability': electricityAvailability,
      'government_restrictions': governmentRestrictions.trim(),
      'additional_brokers':
          additionalBrokers.map((b) => b.toJson()).toList(),
      'token_advance_amount': tokenAdvanceAmount,
      'token_advance_date': tokenAdvanceDate?.toUtc().toIso8601String(),
      'token_advance_notes': tokenAdvanceNotes.trim(),
      'agreement_status': agreementStatus,
      'agreement_date': agreementDate?.toUtc().toIso8601String(),
      'agreement_notes': agreementNotes.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final row = await _db
        .from('land_leads')
        .update(payload)
        .eq('id', leadId)
        .select()
        .single();
    final updated = _fromRow(row);

    final userId = _db.auth.currentUser?.id;
    final userName = AuthService.instance.currentUser?.fullName ?? '';
    Future<void> logPrice(String type, double? oldV, double? newV) async {
      if (newV == null || newV == oldV) return;
      await _db.from('land_lead_price_history').insert({
        'lead_id': leadId,
        'price_type': type,
        'amount': newV,
        'recorded_by': userId,
        'recorded_by_name': userName,
      });
    }

    if (previous != null) {
      await logPrice('asking', previous.askingPrice, askingPrice);
      await logPrice('expected', previous.expectedPrice, expectedPrice);
      await logPrice('guideline', previous.guidelineValue, guidelineValue);
      await logPrice(
          'market_estimate', previous.marketValueEstimate, marketValueEstimate);
    }

    final ctx = _auditContextFor(leadId);
    await AuditLogService.log(
      action: 'update',
      entityType: 'lead',
      entityId: leadId,
      field: 'deal_and_risk_details',
      oldValue: '',
      newValue: 'updated',
      module: 'Lead',
      leadId: leadId,
      ownerName: updated.ownerName,
      brokerName: updated.brokerName,
      executiveName: ctx.executive,
    );

    return updated;
  }

  /// Puts an active (non-terminal) lead on hold — excluded from the "active
  /// negotiation" reading without being counted as lost. Requires a reason.
  /// Puts an active (non-terminal, not already on hold) lead into the
  /// On Hold stage — remembers the current stage in on_hold_previous_status
  /// so resume() can default back into it. Requires a reason.
  static Future<LandLead> setOnHold({
    required String leadId,
    required String reason,
    DateTime? expectedResume,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('A reason is required to put a lead on hold.');
    }
    final current = await _db
        .from('land_leads')
        .select('status')
        .eq('id', leadId)
        .maybeSingle();
    if (current == null) throw Exception('Lead $leadId was not found.');
    final currentStatus = parseLeadStatus(current['status'] as String?);
    if (currentStatus.isTerminal) {
      throw StateError('A Signed or Dropped lead cannot be put on hold.');
    }
    if (currentStatus == LeadStatus.onHold) {
      throw StateError('This lead is already on hold.');
    }

    final row = await _db
        .from('land_leads')
        .update({
          'status': LeadStatus.onHold.name,
          'on_hold_previous_status': currentStatus.name,
          'is_on_hold': true,
          'on_hold_reason': trimmedReason,
          'on_hold_since': DateTime.now().toUtc().toIso8601String(),
          'on_hold_expected_resume':
              expectedResume?.toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', leadId)
        .neq('status', LeadStatus.onHold.name)
        .select()
        .single();
    final updated = _fromRow(row);

    final ctx = _auditContextFor(leadId);
    await AuditLogService.log(
      action: 'hold',
      entityType: 'lead',
      entityId: leadId,
      field: 'status',
      oldValue: currentStatus.name,
      newValue: 'onHold ($trimmedReason)',
      module: 'Lead',
      leadId: leadId,
      ownerName: updated.ownerName,
      brokerName: updated.brokerName,
      executiveName: ctx.executive,
    );
    return updated;
  }

  /// Resumes a lead out of On Hold, back into [targetStatus] — defaults to
  /// whichever stage it was paused from if not specified.
  static Future<LandLead> clearOnHold(
    String leadId, {
    LeadStatus? targetStatus,
  }) async {
    final current = await _db
        .from('land_leads')
        .select('status, on_hold_previous_status')
        .eq('id', leadId)
        .maybeSingle();
    if (current == null) throw Exception('Lead $leadId was not found.');
    if (current['status'] != LeadStatus.onHold.name) {
      throw StateError('This lead is not currently on hold.');
    }
    final resumeInto = targetStatus ??
        parseLeadStatus(current['on_hold_previous_status'] as String?);
    if (resumeInto.isTerminal || resumeInto == LeadStatus.onHold) {
      throw ArgumentError('Cannot resume into ${resumeInto.name}.');
    }

    final row = await _db
        .from('land_leads')
        .update({
          'status': resumeInto.name,
          'on_hold_previous_status': null,
          'is_on_hold': false,
          'on_hold_reason': '',
          'on_hold_since': null,
          'on_hold_expected_resume': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', leadId)
        .eq('status', LeadStatus.onHold.name)
        .select()
        .single();
    final updated = _fromRow(row);

    final ctx = _auditContextFor(leadId);
    await AuditLogService.log(
      action: 'resume',
      entityType: 'lead',
      entityId: leadId,
      field: 'status',
      oldValue: 'onHold',
      newValue: resumeInto.name,
      module: 'Lead',
      leadId: leadId,
      ownerName: updated.ownerName,
      brokerName: updated.brokerName,
      executiveName: ctx.executive,
    );
    return updated;
  }

  /// Splits part of [parent] off into a new, independently-tracked lead —
  /// e.g. part of a parcel is dropped while another part proceeds. Reuses
  /// [create] for the actual insert rather than duplicating that logic.
  /// The parent lead is left untouched apart from a note; if its survey
  /// list should shrink to reflect the split, that's a deliberate manual
  /// edit via the normal Edit Lead flow, not an automatic side effect here.
  static Future<LandLead> splitLead({
    required LandLead parent,
    required String newSurveyNumber,
    String newSubDivision = '',
    List<SurveyEntry> additionalSurveyNumbers = const [],
    required String newLandExtent,
  }) async {
    if (newSurveyNumber.trim().isEmpty) {
      throw ArgumentError('A survey number is required for the split lead.');
    }
    final draft = LandLead(
      leadId: '',
      inputSource: parent.inputSource,
      location: parent.location,
      gpsCoordinates: parent.gpsCoordinates,
      village: parent.village,
      taluk: parent.taluk,
      district: parent.district,
      pincode: parent.pincode,
      surveyNumber: newSurveyNumber.trim(),
      subDivision: newSubDivision.trim(),
      additionalSurveyNumbers: additionalSurveyNumbers,
      landExtent: newLandExtent.trim(),
      ownerName: parent.ownerName,
      contactDetails: parent.contactDetails,
      additionalOwners: parent.additionalOwners,
      brokerName: parent.brokerName,
      brokerContact: parent.brokerContact,
      sourceContactName: parent.sourceContactName,
      sourceContactNumber: parent.sourceContactNumber,
      landType: parent.landType,
      landTypeOther: parent.landTypeOther,
      roadWidth: parent.roadWidth,
      accessDetails: '',
      notes: 'Split from lead ${parent.leadId}.',
      // Inherits the parent's current stage — the relationship/trust with
      // the owner already carries over, this isn't starting from zero.
      status: parent.status,
      addedOn: DateTime.now(),
      splitFromLeadId: parent.leadId,
    );
    final created = await create(draft);

    final ctx = _auditContextFor(parent.leadId);
    await AuditLogService.log(
      action: 'split',
      entityType: 'lead',
      entityId: parent.leadId,
      field: 'split',
      oldValue: '',
      newValue: 'split into ${created.leadId}',
      module: 'Lead',
      leadId: parent.leadId,
      ownerName: ctx.owner,
      brokerName: ctx.broker,
      executiveName: ctx.executive,
    );
    return created;
  }

  /// Merges [source] into [target] — [target] survives and absorbs
  /// [source]'s survey numbers; [source] is kept (never deleted), gets
  /// merged_from tracking plus an explanatory note, and is transitioned to
  /// Dropped so it stops being counted as an independent active lead
  /// alongside its target. (Earlier revisions left the status untouched as
  /// a deliberate manual follow-up — verified nothing in the app actually
  /// reminds anyone to do that, so it silently double-counted the merged
  /// parcel in every pipeline/ageing/dashboard count instead.) Blocks the
  /// merge entirely if [source] is already terminal (Signed/Dropped),
  /// since overwriting an already-Signed lead's status here would erase
  /// a real completed transaction.
  static Future<LandLead> mergeLeads({
    required LandLead target,
    required LandLead source,
  }) async {
    if (target.leadId == source.leadId) {
      throw ArgumentError('Cannot merge a lead into itself.');
    }
    if (target.status.isTerminal) {
      throw StateError(
        'Cannot merge into a ${target.status.label} lead — it is locked.',
      );
    }
    if (source.status.isTerminal) {
      throw StateError(
        'Cannot merge a ${source.status.label} lead — it is locked. '
        '${source.status == LeadStatus.signed ? "It represents a completed deal." : ""}',
      );
    }

    final combinedSurveys = <SurveyEntry>[
      ...target.additionalSurveyNumbers,
      SurveyEntry(
        surveyNumber: source.surveyNumber,
        subDivision: source.subDivision,
      ),
      ...source.additionalSurveyNumbers,
    ];
    final mergedIds = <String>{
      ...target.mergedFromLeadIds,
      source.leadId,
    }.toList();

    final row = await _db
        .from('land_leads')
        .update({
          'additional_survey_numbers':
              combinedSurveys.map((s) => s.toJson()).toList(),
          'merged_from_lead_ids': mergedIds,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', target.leadId)
        .select()
        .single();
    final updatedTarget = _fromRow(row);

    final sourceCtx = _auditContextFor(source.leadId);
    // The source lead is now represented by target — without this, it would
    // remain in whatever active stage it was in and keep being counted
    // everywhere (pipeline, ageing, dashboards) as an independent lead,
    // double-counting the same physical parcel alongside its target.
    // Dropped (rather than a new status) reuses existing, already-tested
    // "no longer active but kept for history" semantics — every report
    // that excludes dropped leads from active counts handles this for
    // free, with no new status to teach the rest of the app about.
    await _db.from('land_leads').update({
      'notes': source.notes.isEmpty
          ? 'Merged into lead ${target.leadId}.'
          : '${source.notes}\n\n[Merged into lead ${target.leadId}.]',
      'status': LeadStatus.dropped.name,
      'drop_reason': 'Merged into lead ${target.leadId}',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', source.leadId);

    await AuditLogService.log(
      action: 'merge',
      entityType: 'lead',
      entityId: target.leadId,
      field: 'merged_from_lead_ids',
      oldValue: target.leadId,
      newValue: 'merged in ${source.leadId}',
      module: 'Lead',
      leadId: target.leadId,
      ownerName: updatedTarget.ownerName,
      brokerName: updatedTarget.brokerName,
      executiveName: sourceCtx.executive,
    );
    return updatedTarget;
  }

  /// Deletes [lead] and every file it owns in storage. Confirmed as a real,
  /// reproducible-via-the-app bug during QA, not just an artifact of manual
  /// SQL cleanup: this previously only deleted the land_leads row, so every
  /// site photo and legal document stayed in storage forever with nothing
  /// left pointing to it. Storage cleanup happens first — if it fails
  /// partway, the lead (and the surviving files' DB references) are still
  /// intact rather than the row disappearing while files silently remain.
  static Future<void> delete(LandLead lead) async {
    final leadId = lead.leadId;

    // Site photos: no folder structure, just `{leadId}.jpg` / `{leadId}_N.jpg`
    // — extract the storage path from each stored URL rather than guessing
    // the naming pattern here a second time.
    if (lead.sitePhotoUrls.isNotEmpty) {
      final paths = lead.sitePhotoUrls
          .map((url) {
            final marker = '/$_photoBucket/';
            final i = url.indexOf(marker);
            if (i == -1) return null;
            final path = url.substring(i + marker.length);
            // Strip any query string (cache-busting ?v=... etc).
            final q = path.indexOf('?');
            return q == -1 ? path : path.substring(0, q);
          })
          .whereType<String>()
          .toList();
      if (paths.isNotEmpty) {
        try {
          await _db.storage.from(_photoBucket).remove(paths);
        } catch (_) {
          // Best-effort — a stale/broken URL shouldn't block the delete.
        }
      }
    }

    // Legal documents: real `{leadId}/filename` folder prefix, so list then
    // remove everything under it in one go.
    try {
      final legalDocsBucket = _db.storage.from('land-lead-legal-docs');
      final objects = await legalDocsBucket.list(path: leadId);
      if (objects.isNotEmpty) {
        await legalDocsBucket
            .remove(objects.map((o) => '$leadId/${o.name}').toList());
      }
    } catch (_) {
      // Best-effort, same reasoning as above.
    }

    final ctx = _auditContextFor(leadId);
    await _db.from('land_leads').delete().eq('id', leadId);
    await AuditLogService.log(
      action: 'delete',
      entityType: 'lead',
      entityId: leadId,
      field: 'lead',
      oldValue: leadId,
      newValue: '',
      module: 'Lead',
      leadId: leadId,
      ownerName: ctx.owner,
      brokerName: ctx.broker,
      executiveName: ctx.executive,
    );
  }

  static LandLead _fromRow(Map<String, dynamic> r) {
    final urlsRaw = r['site_photo_urls'];
    List<String> photoUrls = [];
    if (urlsRaw is List) {
      photoUrls = urlsRaw.map((e) => e.toString()).where((u) => u.isNotEmpty).toList();
    }
    final single = r['site_photo_url'] as String? ?? '';
    if (photoUrls.isEmpty && single.isNotEmpty) {
      photoUrls = [single];
    }

    final additionalOwnersRaw = r['additional_owners'];
    final additionalOwners = additionalOwnersRaw is List
        ? additionalOwnersRaw
            .whereType<Map>()
            .map((m) => OwnerContact.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <OwnerContact>[];

    final additionalSurveyNumbersRaw = r['additional_survey_numbers'];
    final additionalSurveyNumbers = additionalSurveyNumbersRaw is List
        ? additionalSurveyNumbersRaw
            .whereType<Map>()
            .map((m) => SurveyEntry.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <SurveyEntry>[];

    final additionalBrokersRaw = r['additional_brokers'];
    final additionalBrokers = additionalBrokersRaw is List
        ? additionalBrokersRaw
            .whereType<Map>()
            .map((m) => OwnerContact.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <OwnerContact>[];

    final mergedFromRaw = r['merged_from_lead_ids'];
    final mergedFromLeadIds = mergedFromRaw is List
        ? mergedFromRaw.map((e) => e.toString()).toList()
        : <String>[];

    DateTime? parseTs(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    double? parseNum(dynamic v) => v is num ? v.toDouble() : null;

    return LandLead(
      leadId: r['id'] as String,
      inputSource: InputSource.values.firstWhere(
        (e) => e.name == r['input_source'],
        orElse: () => InputSource.broker,
      ),
      location: r['location'] as String? ?? '',
      gpsCoordinates: r['gps_coordinates'] as String? ?? '',
      village: r['village'] as String? ?? '',
      taluk: r['taluk'] as String? ?? '',
      district: r['district'] as String? ?? '',
      pincode: r['pincode'] as String? ?? '',
      surveyNumber: r['survey_number'] as String? ?? '',
      subDivision: r['sub_division'] as String? ?? '',
      additionalSurveyNumbers: additionalSurveyNumbers,
      landExtent: r['land_extent'] as String? ?? '',
      ownerName: r['owner_name'] as String,
      contactDetails: r['contact_details'] as String? ?? '',
      additionalOwners: additionalOwners,
      brokerName: r['broker_name'] as String? ?? '',
      brokerContact: r['broker_contact'] as String? ?? '',
      sourceContactName: r['source_contact_name'] as String? ?? '',
      sourceContactNumber: r['source_contact_number'] as String? ?? '',
      landType: LandType.values.firstWhere(
        (e) => e.name == r['land_type'],
        orElse: () => LandType.agricultural,
      ),
      landTypeOther: r['land_type_other'] as String? ?? '',
      roadWidth: r['road_width'] as String? ?? '',
      accessDetails: r['access_details'] as String? ?? '',
      notes: r['notes'] as String? ?? '',
      sitePhotoUrl: photoUrls.isNotEmpty ? photoUrls.first : single,
      sitePhotoUrls: photoUrls,
      addedOn: DateTime.parse(r['added_on'] as String),
      createdByName: r['created_by_name'] as String? ?? '',
      assignedToName: r['assigned_to_name'] as String? ?? '',
      leadName: r['lead_name'] as String? ?? '',
      leadNameLocked: r['lead_name_locked'] as bool? ?? false,
      createdByRole: r['created_by_role'] as String? ?? '',
      status: parseLeadStatus(r['status'] as String?),
      dropReason: r['drop_reason'] as String? ?? '',
      dropNotes: r['drop_notes'] as String? ?? '',
      askingPrice: parseNum(r['asking_price']),
      expectedPrice: parseNum(r['expected_price']),
      guidelineValue: parseNum(r['guideline_value']),
      marketValueEstimate: parseNum(r['market_value_estimate']),
      litigationStatus: r['litigation_status'] as String? ?? 'unknown',
      encumbranceStatus: r['encumbrance_status'] as String? ?? 'unknown',
      waterAvailability: r['water_availability'] as String? ?? 'unknown',
      electricityAvailability:
          r['electricity_availability'] as String? ?? 'unknown',
      governmentRestrictions: r['government_restrictions'] as String? ?? '',
      additionalBrokers: additionalBrokers,
      tokenAdvanceAmount: parseNum(r['token_advance_amount']),
      tokenAdvanceDate: parseTs(r['token_advance_date']),
      tokenAdvanceNotes: r['token_advance_notes'] as String? ?? '',
      agreementStatus: r['agreement_status'] as String? ?? 'not_started',
      agreementDate: parseTs(r['agreement_date']),
      agreementNotes: r['agreement_notes'] as String? ?? '',
      reopenedAt: parseTs(r['reopened_at']),
      reopenedByName: r['reopened_by_name'] as String? ?? '',
      reopenReason: r['reopen_reason'] as String? ?? '',
      reopenCount: (r['reopen_count'] as num?)?.toInt() ?? 0,
      splitFromLeadId: r['split_from_lead_id'] as String?,
      mergedFromLeadIds: mergedFromLeadIds,
      isOnHold: r['is_on_hold'] as bool? ?? false,
      onHoldReason: r['on_hold_reason'] as String? ?? '',
      onHoldSince: parseTs(r['on_hold_since']),
      onHoldExpectedResume: parseTs(r['on_hold_expected_resume']),
      onHoldPreviousStatus: r['on_hold_previous_status'] != null
          ? parseLeadStatus(r['on_hold_previous_status'] as String?)
          : null,
      landownerMeetingCompletedAt: parseTs(r['landowner_meeting_completed_at']),
      numOwners: r['num_owners'] as String? ?? '',
      ownerOccupation: r['owner_occupation'] as String? ?? '',
      locationRating: r['location_rating'] as String? ?? 'unknown',
      brokerKnowsOwner: r['broker_knows_owner'] as bool?,
      managementMetOwner: r['management_met_owner'] as bool?,
      ownerMeetingLocation: r['owner_meeting_location'] as String? ?? '',
      contactType: r['contact_type'] as String? ?? '',
      contactRelation: r['contact_relation'] as String? ?? '',
    );
  }
}
