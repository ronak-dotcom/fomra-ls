import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/competitor_project.dart';
import 'auth_service.dart';

/// Competitor projects: one shared list (with phases and lead links) for the
/// Competitors menu, the lead page tab and the Home re-check reminders.
/// Everyone signed in can add and update; only an admin deletes a project.
class CompetitorService extends ChangeNotifier {
  CompetitorService._();
  static final instance = CompetitorService._();

  static SupabaseClient get _db => Supabase.instance.client;
  static const bucket = 'competitor-media';
  static const _select = '*, competitor_phases(*), competitor_lead_links(lead_id)';

  final List<CompetitorProject> _all = [];
  bool _loaded = false;
  Future<void>? _loading;
  Object? lastError;

  List<CompetitorProject> get all => List.unmodifiable(_all);
  bool get isLoaded => _loaded;

  /// Tests / previews: use these projects instead of loading.
  @visibleForTesting
  void debugSeed(List<CompetitorProject> projects) {
    _all
      ..clear()
      ..addAll(projects);
    _loaded = true;
    notifyListeners();
  }

  CompetitorProject? byId(String id) =>
      _all.where((p) => p.id == id).firstOrNull;

  Future<void> ensureLoaded({bool force = false}) {
    if (_loaded && !force) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      final rows = await _db
          .from('competitor_projects')
          .select(_select)
          .order('code');
      _all
        ..clear()
        ..addAll([
          for (final r in rows as List)
            CompetitorProject.fromJson(Map<String, dynamic>.from(r as Map)),
        ]);
      lastError = null;
      _loaded = true;
    } catch (e) {
      lastError = e;
      // Keep what was shown before; the screen offers a retry.
      _loaded = _all.isNotEmpty;
    }
    notifyListeners();
  }

  Future<CompetitorProject> _reload(String id) async {
    final row = await _db
        .from('competitor_projects')
        .select(_select)
        .eq('id', id)
        .single();
    final p = CompetitorProject.fromJson(Map<String, dynamic>.from(row));
    final i = _all.indexWhere((x) => x.id == id);
    if (i >= 0) {
      _all[i] = p;
    } else {
      _all.add(p);
      _all.sort((a, b) => a.code.compareTo(b.code));
    }
    notifyListeners();
    return p;
  }

  static String get _me => AuthService.instance.currentUser?.fullName ?? '';
  static String get _myEmail =>
      (AuthService.instance.currentUser?.email ?? '').trim().toLowerCase();

  /// Adds a project with its phases, records today's figures as its first
  /// check, and links it to [linkLeadId] when given. The person adding it
  /// is its owner (management can hand it to someone else later).
  Future<CompetitorProject> create(
    CompetitorProject p, {
    List<CompetitorPhase> phases = const [],
    String? linkLeadId,
    Uint8List? photo,
    String photoName = 'photo.jpg',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await _db
        .from('competitor_projects')
        .insert({
          ...p.toRow(),
          'owner_name': _me,
          'owner_email': _myEmail,
          'created_by_name': _me,
          'source': 'field',
          'last_checked_at': now,
        })
        .select('id')
        .single();
    final id = row['id'].toString();
    if (phases.isNotEmpty) {
      await _db.from('competitor_phases').insert([
        for (var i = 0; i < phases.length; i++) phases[i].toRow(id, i),
      ]);
    }
    int? sum(int? Function(CompetitorPhase) f) {
      final v = [for (final x in phases) if (f(x) != null) f(x)!];
      return v.isEmpty ? null : v.fold<int>(0, (a, b) => a + b);
    }

    await _db.from('competitor_checks').insert({
      'project_id': id,
      'checked_at': now,
      'checked_by_name': _me,
      'pre_launch_price': p.preLaunchPrice,
      'quoted_price': p.quotedPrice,
      'negotiated_price': p.negotiatedPrice,
      'sold': sum((x) => x.sold),
      'available': sum((x) => x.available),
      'notes': 'Added',
    });
    if (linkLeadId != null && linkLeadId.trim().isNotEmpty) {
      await link(id, linkLeadId, reload: false);
    }
    if (photo != null) {
      try {
        await uploadMedia(id, photo,
            fileName: photoName, kind: 'photo', contentType: 'image/jpeg');
      } catch (_) {
        // The project is saved; the photo can be added again on its page.
      }
    }
    return _reload(id);
  }

  /// Saves the project's details and (when given) replaces its phases.
  Future<CompetitorProject> update(
    CompetitorProject p, {
    List<CompetitorPhase>? phases,
  }) async {
    await _db.from('competitor_projects').update(p.toRow()).eq('id', p.id);
    if (phases != null) {
      await _db.from('competitor_phases').delete().eq('project_id', p.id);
      if (phases.isNotEmpty) {
        await _db.from('competitor_phases').insert([
          for (var i = 0; i < phases.length; i++) phases[i].toRow(p.id, i),
        ]);
      }
    }
    return _reload(p.id);
  }

  /// Records a price & sales check: the dated history row, the project's
  /// latest prices, each phase's sold / left, and the re-check clock.
  Future<CompetitorProject> addCheck(
    CompetitorProject p, {
    double? preLaunchPrice,
    double? quotedPrice,
    double? negotiatedPrice,
    required List<CompetitorPhase> phases,
    String notes = '',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    int? sum(int? Function(CompetitorPhase) f) {
      final v = [for (final x in phases) if (f(x) != null) f(x)!];
      return v.isEmpty ? null : v.fold<int>(0, (a, b) => a + b);
    }

    await _db.from('competitor_checks').insert({
      'project_id': p.id,
      'checked_at': now,
      'checked_by_name': _me,
      'pre_launch_price': preLaunchPrice,
      'quoted_price': quotedPrice,
      'negotiated_price': negotiatedPrice,
      'sold': sum((x) => x.sold),
      'available': sum((x) => x.available),
      'notes': notes.trim(),
    });
    await _db.from('competitor_projects').update({
      'pre_launch_price': preLaunchPrice,
      'quoted_price': quotedPrice,
      'negotiated_price': negotiatedPrice,
      'last_checked_at': now,
    }).eq('id', p.id);
    for (final ph in phases) {
      if (ph.id.isEmpty) continue;
      await _db.from('competitor_phases').update({
        'sold': ph.sold,
        'available': ph.available,
      }).eq('id', ph.id);
    }
    return _reload(p.id);
  }

  Future<List<CompetitorCheck>> checks(String projectId) async {
    final rows = await _db
        .from('competitor_checks')
        .select()
        .eq('project_id', projectId)
        .order('checked_at', ascending: false);
    return [
      for (final r in rows as List)
        CompetitorCheck.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<void> link(String projectId, String leadId, {bool reload = true}) async {
    await _db.from('competitor_lead_links').upsert({
      'project_id': projectId,
      'lead_id': leadId.trim(),
      'linked_by_name': _me,
    }, onConflict: 'project_id,lead_id');
    if (reload) await _reload(projectId);
  }

  Future<void> unlink(String projectId, String leadId) async {
    await _db
        .from('competitor_lead_links')
        .delete()
        .eq('project_id', projectId)
        .eq('lead_id', leadId);
    await _reload(projectId);
  }

  /// Management: hand the project (and its re-check reminders) to someone.
  Future<void> reassign(String projectId, String name, String email) async {
    await _db.from('competitor_projects').update({
      'owner_name': name.trim(),
      'owner_email': email.trim().toLowerCase(),
    }).eq('id', projectId);
    await _reload(projectId);
  }

  /// Admin only (the database refuses anyone else).
  Future<void> delete(String projectId) async {
    final media = await this.media(projectId);
    if (media.isNotEmpty) {
      try {
        await _db.storage
            .from(bucket)
            .remove([for (final m in media) m.storagePath]);
      } catch (_) {}
    }
    final deleted = await _db
        .from('competitor_projects')
        .delete()
        .eq('id', projectId)
        .select('id');
    if ((deleted as List).isEmpty) {
      throw Exception('Only an admin can delete a project.');
    }
    _all.removeWhere((p) => p.id == projectId);
    notifyListeners();
  }

  // ── Photos & documents ────────────────────────────────────────────────

  Future<List<CompetitorMedia>> media(String projectId) async {
    final rows = await _db
        .from('competitor_media')
        .select()
        .eq('project_id', projectId)
        .order('created_at', ascending: false);
    return [
      for (final r in rows as List)
        CompetitorMedia.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<void> uploadMedia(
    String projectId,
    Uint8List bytes, {
    required String fileName,
    required String kind,
    required String contentType,
  }) async {
    final safe = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final path =
        '$projectId/${DateTime.now().millisecondsSinceEpoch}_${safe.isEmpty ? 'file' : safe}';
    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    await _db.from('competitor_media').insert({
      'project_id': projectId,
      'kind': kind,
      'storage_path': path,
      'file_name': fileName,
      'content_type': contentType,
      'uploaded_by_name': _me,
    });
  }

  Future<void> deleteMedia(CompetitorMedia m) async {
    try {
      await _db.storage.from(bucket).remove([m.storagePath]);
    } catch (_) {}
    await _db.from('competitor_media').delete().eq('id', m.id);
  }

  /// A one-hour link to view a photo or open a document.
  Future<String> signedUrl(String path) =>
      _db.storage.from(bucket).createSignedUrl(path, 3600);
}
