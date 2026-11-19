import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/lead_drop_reason.dart';

/// The drop reasons everyone picks from, kept in the database
/// (lead_drop_reasons) so a reason management adds in Settings shows on every
/// phone. Only management can change the list (enforced in the database).
/// A copy is kept on the device so the drop form still works offline.
class LeadDropReasonCatalogService extends ChangeNotifier {
  LeadDropReasonCatalogService._();

  static final instance = LeadDropReasonCatalogService._();

  static const _prefsKey = 'lead_drop_reason_catalog_v2';

  List<LeadDropReason> _items = List.of(defaultLeadDropReasons);
  bool _loaded = false;
  DateTime? _loadedAt;

  /// Reasons offered when dropping a lead (hidden ones left out).
  List<LeadDropReason> get current =>
      List.unmodifiable(_items.where((r) => r.active));

  /// Every reason, hidden ones included (Settings, old leads' labels).
  List<LeadDropReason> get all => List.unmodifiable(_items);

  SupabaseClient? get _db {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null; // Not initialised (tests).
    }
  }

  /// Loads the shared list (at most once a minute unless [force]); falls
  /// back to the device copy, then the built-in list, when offline.
  Future<void> load({bool force = false}) async {
    final fresh = _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 1);
    if (_loaded && fresh && !force) return;
    final db = _db;
    if (db != null) {
      try {
        final rows = await db
            .from('lead_drop_reasons')
            .select()
            .order('sort_order')
            .order('created_at');
        final parsed = [
          for (final r in rows as List)
            LeadDropReason.fromJson(Map<String, dynamic>.from(r as Map)),
        ].where((r) => r.id.trim().isNotEmpty && r.label.trim().isNotEmpty);
        if (parsed.isNotEmpty) {
          _items = parsed.toList();
          _loaded = true;
          _loadedAt = DateTime.now();
          notifyListeners();
          await _saveLocal();
          return;
        }
      } catch (e) {
        debugPrint('[drop reasons] could not load shared list: $e');
      }
    }
    if (!_loaded) {
      _items = await _readLocal() ?? List.of(defaultLeadDropReasons);
      _loaded = true;
      notifyListeners();
    }
  }

  Future<List<LeadDropReason>?> _readLocal() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final parsed = decoded
          .whereType<Map>()
          .map((e) => LeadDropReason.fromJson(Map<String, dynamic>.from(e)))
          .where((r) => r.id.trim().isNotEmpty && r.label.trim().isNotEmpty)
          .toList();
      return parsed.isEmpty ? null : parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_items.map((i) => i.toJson()).toList()));
    } catch (_) {}
  }

  /// Saves the whole list (order and visibility) to the database.
  Future<void> _saveShared() async {
    final db = _db;
    if (db == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.from('lead_drop_reasons').upsert([
      for (var i = 0; i < _items.length; i++)
        {
          'id': _items[i].id,
          'label': _items[i].label,
          'active': _items[i].active,
          'sort_order': i + 1,
          'updated_at': now,
        },
    ]);
  }

  /// Replaces the list (management). Throws if the database refuses.
  Future<void> setItems(List<LeadDropReason> items) async {
    final before = _items;
    _items = List<LeadDropReason>.from(items);
    _loaded = true;
    notifyListeners();
    try {
      await _saveShared();
      await _saveLocal();
    } catch (e) {
      _items = before;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addReason(String label) async {
    final clean = label.trim();
    if (clean.isEmpty) return;
    if (_items.any((r) => r.label.toLowerCase() == clean.toLowerCase())) {
      throw StateError('"$clean" is already in the list');
    }
    await setItems([
      ..._items,
      LeadDropReason(id: _uniqueIdFromLabel(clean), label: clean),
    ]);
  }

  /// Renames a reason; leads already dropped for it are relabelled too, so
  /// they keep counting under it.
  Future<void> updateReason(String id, String label) async {
    final clean = label.trim();
    if (clean.isEmpty) return;
    final old = _items.where((r) => r.id == id).firstOrNull;
    if (old == null || old.label == clean) return;
    await setItems([
      for (final r in _items) r.id == id ? r.copyWith(label: clean) : r,
    ]);
    final db = _db;
    if (db == null) return;
    try {
      await db
          .from('land_leads')
          .update({'drop_reason': clean})
          .eq('drop_reason', old.label);
    } catch (e) {
      debugPrint('[drop reasons] could not relabel old leads: $e');
    }
  }

  /// Hides a reason from new drops (or shows it again). Old leads keep it.
  Future<void> setActive(String id, bool active) => setItems([
        for (final r in _items) r.id == id ? r.copyWith(active: active) : r,
      ]);

  /// Reorders among the offered (active) reasons, using the
  /// [ReorderableListView] index convention.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final active = _items.where((r) => r.active).toList();
    final hidden = _items.where((r) => !r.active).toList();
    if (newIndex > oldIndex) newIndex -= 1;
    final item = active.removeAt(oldIndex);
    active.insert(newIndex, item);
    await setItems([...active, ...hidden]);
  }

  LeadDropReason? findByRaw(String? raw) =>
      leadDropReasonFromRaw(raw, catalog: _items);

  String displayLabelForRaw(String? raw) =>
      findByRaw(raw)?.label ?? (raw?.trim().isEmpty ?? true ? '—' : raw!.trim());

  String _uniqueIdFromLabel(String label) {
    final slug = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = slug.isEmpty ? 'reason' : slug;
    var candidate = base;
    var suffix = 2;
    while (_items.any((item) => item.id == candidate)) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }
}
