import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/land_lead.dart';
import '../screens/task_management/task_management_screen.dart' as tasks;
import 'app_store.dart';
import 'land_lead_service.dart';
import 'offline_queue_store.dart';
import 'voice_note_service.dart';

/// Watches connectivity and drains the offline outbox when the network returns.
class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService._();
  static final instance = OfflineSyncService._();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = true;
  bool _syncing = false;
  int _pending = 0;
  String? _lastSyncMessage;

  bool get isOnline => _online;
  bool get isSyncing => _syncing;
  int get pendingCount => _pending;
  String? get lastSyncMessage => _lastSyncMessage;

  Future<void> start() async {
    await _refreshConnectivity();
    await refreshPendingCount();
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen((results) async {
      final next = results.any((r) => r != ConnectivityResult.none);
      final wasOffline = !_online;
      _online = next;
      notifyListeners();
      if (wasOffline && _online) {
        await syncNow();
      }
    });
  }

  Future<void> disposeService() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _refreshConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _online = results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      _online = true;
    }
    notifyListeners();
  }

  Future<void> refreshPendingCount() async {
    _pending = await OfflineQueueStore.pendingCount;
    notifyListeners();
  }

  Future<void> enqueueCreateLead({
    required LandLead lead,
    List<Uint8List> photoBytes = const [],
  }) async {
    final blobIds = <String>[];
    for (final bytes in photoBytes) {
      blobIds.add(await OfflineQueueStore.putBlob(bytes, ext: 'jpg'));
    }
    final tempId = lead.leadId.isNotEmpty
        ? lead.leadId
        : 'offline_${DateTime.now().millisecondsSinceEpoch}';
    final offlineLead = lead.copyWith();
    // Preserve temp id in payload — LandLead.leadId is final via constructor.
    await OfflineQueueStore.enqueue(OfflineOp(
      id: 'op_${DateTime.now().microsecondsSinceEpoch}',
      type: OfflineOpType.createLead,
      createdAt: DateTime.now().toUtc(),
      payload: {
        'temp_id': tempId,
        'lead': _leadToMap(offlineLead, overrideId: tempId),
      },
      blobIds: blobIds,
    ));
    AppStore.instance.addLead(_leadFromMap(
      _leadToMap(offlineLead, overrideId: tempId),
    ));
    await refreshPendingCount();
  }

  Future<void> enqueueUpdateLead({
    required LandLead lead,
    List<Uint8List> photoBytes = const [],
  }) async {
    final blobIds = <String>[];
    for (final bytes in photoBytes) {
      blobIds.add(await OfflineQueueStore.putBlob(bytes, ext: 'jpg'));
    }
    await OfflineQueueStore.enqueue(OfflineOp(
      id: 'op_${DateTime.now().microsecondsSinceEpoch}',
      type: OfflineOpType.updateLead,
      createdAt: DateTime.now().toUtc(),
      payload: {'lead': _leadToMap(lead)},
      blobIds: blobIds,
    ));
    AppStore.instance.replaceLead(lead);
    await refreshPendingCount();
  }

  Future<void> enqueuePhoto({
    required String leadId,
    required Uint8List bytes,
  }) async {
    final blobId = await OfflineQueueStore.putBlob(bytes, ext: 'jpg');
    await OfflineQueueStore.enqueue(OfflineOp(
      id: 'op_${DateTime.now().microsecondsSinceEpoch}',
      type: OfflineOpType.uploadPhoto,
      createdAt: DateTime.now().toUtc(),
      payload: {'lead_id': leadId},
      blobIds: [blobId],
    ));
    await refreshPendingCount();
  }

  Future<void> enqueueVoiceNote({
    required String leadId,
    required Uint8List bytes,
    required int durationMs,
  }) async {
    final blobId = await OfflineQueueStore.putBlob(bytes, ext: 'm4a');
    await OfflineQueueStore.enqueue(OfflineOp(
      id: 'op_${DateTime.now().microsecondsSinceEpoch}',
      type: OfflineOpType.uploadVoiceNote,
      createdAt: DateTime.now().toUtc(),
      payload: {
        'lead_id': leadId,
        'duration_ms': durationMs,
      },
      blobIds: [blobId],
    ));
    await refreshPendingCount();
  }

  Future<void> enqueueCreateTask({
    required String title,
    required String description,
    required String module,
    required List<String> assignedTo,
    required DateTime dueDate,
    required tasks.TaskPriority priority,
  }) async {
    final local = tasks.Task(
      id: 'offline_task_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      description: description,
      module: module,
      assignedTo: assignedTo,
      dueDate: dueDate,
      priority: priority,
      status: tasks.TaskStatus.todo,
      createdAt: DateTime.now(),
    );
    tasks.sharedTasks.insert(0, local);
    await OfflineQueueStore.enqueue(OfflineOp(
      id: 'op_${DateTime.now().microsecondsSinceEpoch}',
      type: OfflineOpType.createTask,
      createdAt: DateTime.now().toUtc(),
      payload: {
        'id': local.id,
        'title': title,
        'description': description,
        'module': module,
        'assigned_to': assignedTo,
        'due_date': dueDate.toIso8601String(),
        'priority': priority.name,
      },
    ));
    await refreshPendingCount();
  }

  /// Drain the queue. Safe to call repeatedly.
  Future<int> syncNow() async {
    if (_syncing) return 0;
    await _refreshConnectivity();
    if (!_online) {
      _lastSyncMessage = 'Still offline — changes stay queued.';
      notifyListeners();
      return 0;
    }

    _syncing = true;
    notifyListeners();
    var synced = 0;
    try {
      final ops = await OfflineQueueStore.load();
      for (final op in [...ops]) {
        try {
          await _process(op);
          await OfflineQueueStore.remove(op.id);
          synced++;
        } catch (e) {
          op.attempts += 1;
          op.lastError = e.toString();
          await OfflineQueueStore.update(op);
          // Stop on first hard failure to preserve order for dependent ops.
          if (op.attempts >= 5) continue;
          break;
        }
      }
      _lastSyncMessage = synced > 0
          ? 'Synced $synced queued change(s).'
          : (ops.isEmpty ? 'Nothing to sync.' : 'Sync paused — will retry.');
    } finally {
      _syncing = false;
      await refreshPendingCount();
    }
    return synced;
  }

  Future<void> _process(OfflineOp op) async {
    switch (op.type) {
      case OfflineOpType.createLead:
        await _syncCreateLead(op);
      case OfflineOpType.updateLead:
        await _syncUpdateLead(op);
      case OfflineOpType.uploadPhoto:
        await _syncPhoto(op);
      case OfflineOpType.uploadVoiceNote:
        await _syncVoice(op);
      case OfflineOpType.createTask:
        // Tasks remain local (sharedTasks); mark as synced by removing op.
        // Persist note is already in sharedTasks from enqueue.
        break;
    }
  }

  Future<void> _syncCreateLead(OfflineOp op) async {
    final map = Map<String, dynamic>.from(op.payload['lead'] as Map);
    final tempId = op.payload['temp_id'] as String? ?? map['lead_id'] as String;
    final photos = <Uint8List>[];
    for (final id in op.blobIds) {
      final b = await OfflineQueueStore.getBlob(id);
      if (b != null) photos.add(b);
    }
    final draft = _leadFromMap(map);
    final created = await LandLeadService.create(
      draft,
      sitePhotoBytes: photos,
    );
    AppStore.instance.removeLead(tempId);
    AppStore.instance.addLead(created);
  }

  Future<void> _syncUpdateLead(OfflineOp op) async {
    final map = Map<String, dynamic>.from(op.payload['lead'] as Map);
    final photos = <Uint8List>[];
    for (final id in op.blobIds) {
      final b = await OfflineQueueStore.getBlob(id);
      if (b != null) photos.add(b);
    }
    final lead = _leadFromMap(map);
    final updated = await LandLeadService.update(
      lead,
      sitePhotoBytes: photos,
    );
    AppStore.instance.replaceLead(updated);
  }

  Future<void> _syncPhoto(OfflineOp op) async {
    final leadId = op.payload['lead_id'] as String;
    final lead = AppStore.instance.leads
        .where((l) => l.leadId == leadId)
        .firstOrNull;
    if (lead == null) throw Exception('Lead $leadId not found for photo sync');
    final photos = <Uint8List>[];
    for (final id in op.blobIds) {
      final b = await OfflineQueueStore.getBlob(id);
      if (b != null) photos.add(b);
    }
    if (photos.isEmpty) return;
    final updated = await LandLeadService.update(
      lead,
      sitePhotoBytes: photos,
    );
    AppStore.instance.replaceLead(updated);
  }

  Future<void> _syncVoice(OfflineOp op) async {
    final leadId = op.payload['lead_id'] as String;
    final durationMs = op.payload['duration_ms'] as int? ?? 0;
    final blobId = op.blobIds.firstOrNull;
    if (blobId == null) return;
    final bytes = await OfflineQueueStore.getBlob(blobId);
    if (bytes == null) return;
    await VoiceNoteService.uploadAndAttach(
      leadId: leadId,
      bytes: bytes,
      durationMs: durationMs,
    );
  }

  static Map<String, dynamic> _leadToMap(
    LandLead lead, {
    String? overrideId,
  }) =>
      {
        'lead_id': overrideId ?? lead.leadId,
        'lead_name': lead.leadName,
        'lead_name_locked': lead.leadNameLocked,
        'input_source': lead.inputSource.name,
        'location': lead.location,
        'gps_coordinates': lead.gpsCoordinates,
        'village': lead.village,
        'taluk': lead.taluk,
        'district': lead.district,
        'pincode': lead.pincode,
        'survey_number': lead.surveyNumber,
        'sub_division': lead.subDivision,
        'additional_survey_numbers':
            lead.additionalSurveyNumbers.map((s) => s.toJson()).toList(),
        'land_extent': lead.landExtent,
        'owner_name': lead.ownerName,
        'contact_details': lead.contactDetails,
        'additional_owners':
            lead.additionalOwners.map((o) => o.toJson()).toList(),
        'broker_name': lead.brokerName,
        'broker_contact': lead.brokerContact,
        'additional_brokers':
            lead.additionalBrokers.map((o) => o.toJson()).toList(),
        'source_contact_name': lead.sourceContactName,
        'source_contact_number': lead.sourceContactNumber,
        'land_type': lead.landType.name,
        'land_type_other': lead.landTypeOther,
        'road_width': lead.roadWidth,
        'access_details': lead.accessDetails,
        'notes': lead.notes,
        'site_photo_url': lead.sitePhotoUrl,
        'site_photo_urls': lead.sitePhotoUrls,
        'added_on': lead.addedOn.toIso8601String(),
        'created_by_name': lead.createdByName,
        'created_by_role': lead.createdByRole,
        'status': lead.status.name,
        'drop_reason': lead.dropReason,
        'drop_notes': lead.dropNotes,
      };

  static LandLead _leadFromMap(Map<String, dynamic> m) {
    return LandLead(
      leadId: m['lead_id'] as String? ?? '',
      leadName: m['lead_name'] as String? ?? '',
      leadNameLocked: m['lead_name_locked'] as bool? ?? false,
      inputSource: InputSource.values.firstWhere(
        (e) => e.name == m['input_source'],
        orElse: () => InputSource.landowner,
      ),
      location: m['location'] as String? ?? '',
      gpsCoordinates: m['gps_coordinates'] as String? ?? '',
      village: m['village'] as String? ?? '',
      taluk: m['taluk'] as String? ?? '',
      district: m['district'] as String? ?? '',
      pincode: m['pincode'] as String? ?? '',
      surveyNumber: m['survey_number'] as String? ?? '',
      subDivision: m['sub_division'] as String? ?? '',
      additionalSurveyNumbers: (m['additional_survey_numbers'] as List?)
              ?.whereType<Map>()
              .map((e) => SurveyEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      landExtent: m['land_extent'] as String? ?? '',
      ownerName: m['owner_name'] as String? ?? '',
      contactDetails: m['contact_details'] as String? ?? '',
      additionalOwners: (m['additional_owners'] as List?)
              ?.whereType<Map>()
              .map((e) => OwnerContact.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      brokerName: m['broker_name'] as String? ?? '',
      brokerContact: m['broker_contact'] as String? ?? '',
      additionalBrokers: (m['additional_brokers'] as List?)
              ?.whereType<Map>()
              .map((e) => OwnerContact.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      sourceContactName: m['source_contact_name'] as String? ?? '',
      sourceContactNumber: m['source_contact_number'] as String? ?? '',
      landType: LandType.values.firstWhere(
        (e) => e.name == m['land_type'],
        orElse: () => LandType.agricultural,
      ),
      landTypeOther: m['land_type_other'] as String? ?? '',
      roadWidth: m['road_width'] as String? ?? '',
      accessDetails: m['access_details'] as String? ?? '',
      notes: m['notes'] as String? ?? '',
      sitePhotoUrl: m['site_photo_url'] as String? ?? '',
      sitePhotoUrls: (m['site_photo_urls'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      addedOn: DateTime.tryParse(m['added_on'] as String? ?? '') ??
          DateTime.now(),
      createdByName: m['created_by_name'] as String? ?? '',
      createdByRole: m['created_by_role'] as String? ?? '',
      status: parseLeadStatus(m['status'] as String?),
      dropReason: m['drop_reason'] as String? ?? '',
      dropNotes: m['drop_notes'] as String? ?? '',
    );
  }
}

// Keep dart:convert import used if needed for debugging.
const _ = jsonEncode;
