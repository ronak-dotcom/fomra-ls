import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/land_lead.dart';
import 'auth_service.dart';

/// A broker in the directory: one per mobile number, with the one name the
/// app shows for them, plus every spelling the team has typed.
class BrokerEntry {
  final String phone;
  final String displayName;
  final List<String> aliases;

  /// Spellings genuinely differ; management picks or types the name.
  final bool needsReview;
  final String reviewedBy;

  const BrokerEntry({
    required this.phone,
    required this.displayName,
    this.aliases = const [],
    this.needsReview = false,
    this.reviewedBy = '',
  });

  factory BrokerEntry.fromJson(Map<String, dynamic> j) => BrokerEntry(
        phone: j['phone'] as String,
        displayName: (j['display_name'] as String? ?? '').trim(),
        aliases: (j['aliases'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        needsReview: j['needs_review'] as bool? ?? false,
        reviewedBy: j['reviewed_by'] as String? ?? '',
      );

  /// "98413 09113".
  String get phoneLabel => BrokerDirectory.formatPhone(phone);
}

/// The Broker Directory (`brokers` table): brokers are identified by mobile
/// number, so a spelling slip ("kalai" vs "Kalaiarasu") no longer splits one
/// broker into two. Leads keep what was typed; everything that shows or
/// groups brokers goes through [keyFor] and [nameFor].
class BrokerDirectory extends ChangeNotifier {
  BrokerDirectory._();
  static final BrokerDirectory instance = BrokerDirectory._();

  static SupabaseClient get _db => Supabase.instance.client;

  Map<String, BrokerEntry> _byPhone = const {};
  bool _loaded = false;
  Future<void>? _inFlight;
  DateTime? _loadedAt;

  bool get isLoaded => _loaded;
  List<BrokerEntry> get all => _byPhone.values.toList();
  BrokerEntry? byPhone(String phone) => _byPhone[phoneKey(phone)];

  /// Last 10 digits of a phone number, or null with fewer than 10 digits —
  /// the same rule as the database's broker_phone_key().
  static String? phoneKey(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return null;
    return digits.substring(digits.length - 10);
  }

  /// "9841309113" -> "98413 09113".
  static String formatPhone(String phone) {
    final k = phoneKey(phone);
    if (k == null) return phone.trim();
    return '${k.substring(0, 5)} ${k.substring(5)}';
  }

  /// Spelling-insensitive form of a name: lower case, letters only.
  static String nameKey(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  /// What a lead's broker is grouped by: the mobile number when it has one,
  /// else (older leads with no number) the name.
  static String keyFor(LandLead lead) =>
      phoneKey(lead.brokerContact) ??
      'name:${lead.brokerName.trim().toLowerCase()}';

  /// The name to show for a lead's broker: the directory's name for their
  /// number, else what was typed on the lead.
  String nameFor(LandLead lead) {
    final k = phoneKey(lead.brokerContact);
    final entry = k == null ? null : _byPhone[k];
    final name = entry?.displayName ?? '';
    return name.isNotEmpty ? name : lead.brokerName.trim();
  }

  /// Loads once, then at most every 2 minutes, unless [force].
  Future<void> ensureLoaded({bool force = false}) {
    final fresh = _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 2);
    if (!force && _loaded && fresh) return Future.value();
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    try {
      final rows = await _db.from('brokers').select().limit(10000);
      _byPhone = {
        for (final r in rows as List)
          (r as Map)['phone'] as String:
              BrokerEntry.fromJson(Map<String, dynamic>.from(r)),
      };
      _loaded = true;
      _loadedAt = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('BrokerDirectory load failed: $e');
    }
  }

  /// Known brokers whose name or number matches [query], best first: exact
  /// and prefix matches, then near-spellings ("kalai" finds Kalaiarasu,
  /// "sabestin" finds Sebastin). Searches every spelling seen, not just the
  /// display name.
  List<BrokerEntry> suggest(String query, {int limit = 6}) {
    final q = nameKey(query);
    final digits = query.replaceAll(RegExp(r'\D'), '');
    if (q.length < 2 && digits.length < 3) return const [];
    final scored = <(int, BrokerEntry)>[];
    for (final b in _byPhone.values) {
      var best = 1 << 20;
      if (digits.length >= 3 && b.phone.contains(digits)) best = 0;
      if (q.length >= 2) {
        for (final n in {b.displayName, ...b.aliases}) {
          final k = nameKey(n);
          if (k.isEmpty) continue;
          int s;
          if (k == q) {
            s = 0;
          } else if (k.startsWith(q)) {
            s = 1;
          } else if (k.contains(q)) {
            s = 2;
          } else {
            // Near-spelling: compare against the same-length start of the
            // name, so "kalai" vs "Kalaiarasu" and "sabestin" vs "sebastin"
            // both count.
            final head = k.length > q.length ? k.substring(0, q.length) : k;
            final d = _editDistance(q, head);
            s = d <= (q.length >= 6 ? 2 : 1) ? 3 + d : 1 << 20;
          }
          if (s < best) best = s;
        }
      }
      if (best < (1 << 20)) scored.add((best, b));
    }
    scored.sort((a, b) {
      final byScore = a.$1.compareTo(b.$1);
      return byScore != 0
          ? byScore
          : a.$2.displayName.toLowerCase().compareTo(
              b.$2.displayName.toLowerCase());
    });
    return [for (final s in scored.take(limit)) s.$2];
  }

  static int _editDistance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// Management: set the one name shown for a number; clears the review flag.
  Future<void> rename(String phone, String displayName) async {
    final name = displayName.trim();
    if (name.isEmpty) throw ArgumentError('Name cannot be empty');
    await _db.from('brokers').update({
      'display_name': name,
      'needs_review': false,
      'reviewed_by': AuthService.instance.currentUser?.fullName ?? '',
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('phone', phone);
    await ensureLoaded(force: true);
  }

  /// Management: move every lead filed under [fromPhone] (a mistyped number)
  /// onto [toPhone]. Returns how many leads moved.
  Future<int> merge(String fromPhone, String toPhone) async {
    final moved = await _db.rpc('merge_broker_phone',
        params: {'from_phone': fromPhone, 'to_phone': toPhone});
    await ensureLoaded(force: true);
    return (moved as num?)?.toInt() ?? 0;
  }

  /// Tests: use these brokers instead of the database.
  @visibleForTesting
  void debugSeed(List<BrokerEntry> entries) {
    _byPhone = {for (final e in entries) e.phone: e};
    _loaded = true;
    _loadedAt = DateTime.now();
    notifyListeners();
  }
}

extension LeadBrokerDisplay on LandLead {
  /// The broker's name as shown everywhere: the Broker Directory's name for
  /// their mobile number, else what was typed on the lead.
  String get brokerDisplayName => BrokerDirectory.instance.nameFor(this);
}
