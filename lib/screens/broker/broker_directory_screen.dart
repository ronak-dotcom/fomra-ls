import 'package:flutter/material.dart';

import '../../models/land_lead.dart';
import '../../services/app_store.dart';
import '../../services/broker_directory.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';
import '../land_lead/filtered_leads_screen.dart';

/// Management: the Broker Directory. One broker per mobile number; where the
/// team typed that number under genuinely different names, management picks
/// or types the one name to show. A mistyped number can be merged into the
/// right one, moving its leads across.
class BrokerDirectoryScreen extends StatefulWidget {
  const BrokerDirectoryScreen({super.key});

  @override
  State<BrokerDirectoryScreen> createState() => _BrokerDirectoryScreenState();
}

class _BrokerDirectoryScreenState extends State<BrokerDirectoryScreen> {
  String _query = '';
  bool _reviewOnly = false;

  @override
  void initState() {
    super.initState();
    BrokerDirectory.instance.addListener(_rebuild);
    AppStore.instance.addListener(_rebuild);
    BrokerDirectory.instance.ensureLoaded(force: true);
  }

  @override
  void dispose() {
    BrokerDirectory.instance.removeListener(_rebuild);
    AppStore.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Leads per broker number (only the leads this viewer can see).
  Map<String, List<LandLead>> get _leadsByPhone {
    final map = <String, List<LandLead>>{};
    for (final l in AppStore.instance.leads) {
      final k = BrokerDirectory.phoneKey(l.brokerContact);
      if (k != null && l.brokerName.trim().isNotEmpty) {
        (map[k] ??= []).add(l);
      }
    }
    return map;
  }

  /// Other numbers saved under the same spelling — often one number typed
  /// wrong (a missing or extra digit).
  List<BrokerEntry> _sameNameOthers(BrokerEntry b, List<BrokerEntry> all) {
    final keys = {
      for (final n in {b.displayName, ...b.aliases}) BrokerDirectory.nameKey(n),
    }..remove('');
    return [
      for (final o in all)
        if (o.phone != b.phone &&
            {o.displayName, ...o.aliases}
                .any((n) => keys.contains(BrokerDirectory.nameKey(n))))
          o,
    ];
  }

  Future<void> _setName(BrokerEntry b) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SetNameDialog(entry: b),
    );
    if (name == null || !mounted) return;
    try {
      await BrokerDirectory.instance.rename(b.phone, name);
      if (mounted) AppFeedback.success(context, 'Saved: ${b.phoneLabel} is "$name".');
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not save: $e');
    }
  }

  Future<void> _merge(BrokerEntry from, List<BrokerEntry> candidates) async {
    final target = await showDialog<BrokerEntry>(
      context: context,
      builder: (_) => _MergeDialog(from: from, suggested: candidates),
    );
    if (target == null || !mounted) return;
    try {
      final moved = await BrokerDirectory.instance.merge(from.phone, target.phone);
      if (!mounted) return;
      AppFeedback.success(
        context,
        'Merged into ${target.displayName} (${target.phoneLabel}) · '
        '$moved lead${moved == 1 ? '' : 's'} moved.',
      );
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not merge: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dir = BrokerDirectory.instance;
    final all = dir.all;
    final leadsByPhone = _leadsByPhone;
    final q = _query.trim().toLowerCase();
    final digits = _query.replaceAll(RegExp(r'\D'), '');
    final reviewCount = all.where((b) => b.needsReview).length;
    final shown = all.where((b) {
      if (_reviewOnly && !b.needsReview) return false;
      if (q.isEmpty) return true;
      if (digits.length >= 3 && b.phone.contains(digits)) return true;
      return {b.displayName, ...b.aliases}
          .any((n) => n.toLowerCase().contains(q));
    }).toList()
      ..sort((a, b) {
        if (a.needsReview != b.needsReview) return a.needsReview ? -1 : 1;
        final byLeads = (leadsByPhone[b.phone]?.length ?? 0)
            .compareTo(leadsByPhone[a.phone]?.length ?? 0);
        return byLeads != 0
            ? byLeads
            : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });

    return Scaffold(
      backgroundColor: context.fomraPageBg,
      appBar: AppBar(
        title: const Text('Broker Directory'),
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
      ),
      body: !dir.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: FomraLayout.pagePadding(context),
              children: [
                Text(
                  'Brokers are tracked by mobile number. Each number shows one '
                  'name everywhere in the app. Where the team typed a number '
                  'under different names, pick or type the right one.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: context.fomraTextSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search name or number…',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                    label: Text('All (${all.length})'),
                    selected: !_reviewOnly,
                    onSelected: (_) => setState(() => _reviewOnly = false),
                  ),
                  ChoiceChip(
                    label: Text('Needs review ($reviewCount)'),
                    selected: _reviewOnly,
                    onSelected: (_) => setState(() => _reviewOnly = true),
                  ),
                ]),
                const SizedBox(height: 14),
                if (shown.isEmpty)
                  AppCard(
                    child: EmptyState(
                      icon: Icons.handshake_outlined,
                      title: _reviewOnly
                          ? 'Nothing to review'
                          : 'No brokers match',
                      message: _reviewOnly
                          ? 'Every broker number has one confirmed name.'
                          : 'Try a different name or number.',
                    ),
                  ),
                for (final b in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _BrokerCard(
                      entry: b,
                      leads: leadsByPhone[b.phone] ?? const [],
                      sameNameOthers: _sameNameOthers(b, all),
                      onSetName: () => _setName(b),
                      onMerge: () => _merge(b, _sameNameOthers(b, all)),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _BrokerCard extends StatelessWidget {
  final BrokerEntry entry;
  final List<LandLead> leads;
  final List<BrokerEntry> sameNameOthers;
  final VoidCallback onSetName;
  final VoidCallback onMerge;

  const _BrokerCard({
    required this.entry,
    required this.leads,
    required this.sameNameOthers,
    required this.onSetName,
    required this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    final otherSpellings = entry.aliases
        .where((a) => a.trim() != entry.displayName.trim())
        .toList();
    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.phoneLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.fomraTextSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.needsReview)
                const _Pill(label: 'Needs review', color: AppColors.warning)
              else if (entry.reviewedBy.isNotEmpty)
                const _Pill(label: 'Confirmed', color: AppColors.success),
            ],
          ),
          if (otherSpellings.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Also typed as',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: context.fomraTextTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in otherSpellings)
                  _Pill(label: a, color: AppColors.purple),
              ],
            ),
          ],
          if (sameNameOthers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.info_outline_rounded,
                  size: 15, color: AppColors.info),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Same name on another number: '
                  '${sameNameOthers.map((o) => o.phoneLabel).join(', ')}. '
                  'If that number was mistyped, merge it.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.fomraTextSecondary,
                  ),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: leads.isEmpty
                    ? null
                    : () => FilteredLeadsScreen.openList(
                          context,
                          title: entry.displayName,
                          subtitle: 'Broker · ${entry.phoneLabel}',
                          leads: leads,
                        ),
                icon: const Icon(Icons.list_alt_rounded, size: 18),
                label: Text('${leads.length} land${leads.length == 1 ? '' : 's'}'),
              ),
              FilledButton.tonalIcon(
                onPressed: onSetName,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(entry.needsReview ? 'Pick name' : 'Edit name'),
              ),
              OutlinedButton.icon(
                onPressed: onMerge,
                icon: const Icon(Icons.merge_type_rounded, size: 18),
                label: const Text('Merge into…'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
}

/// Pick one of the spellings seen, or type a new name.
class _SetNameDialog extends StatefulWidget {
  final BrokerEntry entry;
  const _SetNameDialog({required this.entry});

  @override
  State<_SetNameDialog> createState() => _SetNameDialogState();
}

class _SetNameDialogState extends State<_SetNameDialog> {
  late final _ctrl = TextEditingController(text: widget.entry.displayName);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spellings = {widget.entry.displayName, ...widget.entry.aliases}
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return AlertDialog(
      title: Text('Name for ${widget.entry.phoneLabel}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tap a spelling the team used, or type the correct name.',
              style: TextStyle(fontSize: 13, color: context.fomraTextSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in spellings)
                  ChoiceChip(
                    label: Text(s),
                    selected: _ctrl.text.trim() == s.trim(),
                    onSelected: (_) => setState(() => _ctrl.text = s.trim()),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Broker name'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _ctrl.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Save name'),
        ),
      ],
    );
  }
}

/// Choose the right number to move a (mistyped) number's leads onto.
class _MergeDialog extends StatefulWidget {
  final BrokerEntry from;
  final List<BrokerEntry> suggested;
  const _MergeDialog({required this.from, required this.suggested});

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  String _query = '';
  BrokerEntry? _target;

  @override
  Widget build(BuildContext context) {
    final options = _query.trim().isEmpty
        ? widget.suggested
        : BrokerDirectory.instance
            .suggest(_query, limit: 8)
            .where((b) => b.phone != widget.from.phone)
            .toList();
    return AlertDialog(
      title: Text('Merge ${widget.from.phoneLabel}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All leads saved under ${widget.from.phoneLabel} '
              '(${widget.from.displayName}) move to the broker you pick, and '
              'this number is removed. Use this when a number was mistyped.',
              style: TextStyle(fontSize: 13, color: context.fomraTextSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: widget.suggested.isEmpty,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search the right broker…',
              ),
            ),
            const SizedBox(height: 8),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Type a name or number to find the broker.',
                  style: TextStyle(color: context.fomraTextTertiary),
                ),
              ),
            for (final o in options)
              ListTile(
                onTap: () => setState(() => _target = o),
                leading: Icon(
                  _target?.phone == o.phone
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: _target?.phone == o.phone
                      ? AppColors.primary
                      : context.fomraTextTertiary,
                ),
                title: Text(o.displayName),
                subtitle: Text(o.phoneLabel),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _target == null
              ? null
              : () => Navigator.pop(context, _target),
          child: Text(_target == null
              ? 'Merge'
              : 'Merge into ${_target!.displayName}'),
        ),
      ],
    );
  }
}
