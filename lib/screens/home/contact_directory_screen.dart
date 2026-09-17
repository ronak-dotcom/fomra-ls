import 'package:flutter/material.dart';

import '../../utils/contact_directory.dart';
import '../../models/land_lead.dart';
import '../../services/app_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/contact_call_whatsapp.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/ui/app_components.dart';
import '../land_lead/lead_detail_screen.dart';

class ContactDirectoryScreen extends StatefulWidget {
  final ContactDirectoryKind kind;

  const ContactDirectoryScreen({super.key, required this.kind});

  static void open(BuildContext context, {required ContactDirectoryKind kind}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactDirectoryScreen(kind: kind),
      ),
    );
  }

  @override
  State<ContactDirectoryScreen> createState() => _ContactDirectoryScreenState();
}

class _ContactDirectoryScreenState extends State<ContactDirectoryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    AppStore.instance.addListener(_rebuild);
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim()));
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_rebuild);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  String get _title => widget.kind == ContactDirectoryKind.owner
      ? 'Owner details'
      : 'Broker details';

  String get _subtitle => widget.kind == ContactDirectoryKind.owner
      ? 'Landowners across your leads'
      : 'Brokers linked to your leads';

  IconData get _headerIcon => widget.kind == ContactDirectoryKind.owner
      ? Icons.person_outline
      : Icons.handshake_outlined;

  List<ContactDirectoryEntry> get _entries {
    final all =
        buildContactDirectoryEntries(AppStore.instance.visibleLeads, widget.kind);
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where(
          (e) =>
              e.name.toLowerCase().contains(q) ||
              e.contact.toLowerCase().contains(q),
        )
        .toList();
  }

  void _openLead(LandLead lead) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeadDetailScreen(lead: lead),
      ),
    );
  }

  void _onEntryTap(ContactDirectoryEntry entry) {
    if (entry.leads.length == 1) {
      _openLead(entry.leads.first);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.fomraSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  entry.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: context.fomraTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.leads.length} leads',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.fomraTextSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: entry.leads.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: context.fomraBorder.withValues(alpha: 0.7),
                    ),
                    itemBuilder: (_, i) {
                      final lead = entry.leads[i];
                      final location = [
                        lead.location,
                        lead.village,
                        lead.district,
                      ].where((s) => s.trim().isNotEmpty).join(', ');
                      final showId =
                          lead.displayName != 'Lead #${lead.leadId}';
                      final subtitleText = [
                        if (showId) '#${lead.leadId}',
                        if (location.isNotEmpty) location,
                      ].join(' · ');
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          lead.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        subtitle: subtitleText.isEmpty
                            ? null
                            : Text(
                                subtitleText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.pop(ctx);
                          _openLead(lead);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;

    return FomraAppShell(
      currentRoute: '/home',
      appBar: FomraAppBar(
        moduleName: _title,
      ),
      backgroundColor: context.fomraPageBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: FomraLayout.pagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: _title,
                  subtitle:
                      '${entries.length} contact${entries.length == 1 ? '' : 's'} · $_subtitle',
                  icon: _headerIcon,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by name or number…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: context.fomraSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.fomraBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.fomraBorder),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: EmptyState(
                      icon: _headerIcon,
                      title: _query.isEmpty
                          ? 'No contacts yet'
                          : 'No matches found',
                      message: _query.isEmpty
                          ? 'Add leads with ${widget.kind == ContactDirectoryKind.owner ? 'owner' : 'broker'} details to see them here.'
                          : 'Try a different name or phone number.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: context.fomraBorder.withValues(alpha: 0.7),
                    ),
                    itemBuilder: (_, index) {
                      final entry = entries[index];
                      return _ContactDirectoryRow(
                        entry: entry,
                        accent: widget.kind == ContactDirectoryKind.owner
                            ? AppColors.success
                            : AppColors.secondary,
                        onTap: () => _onEntryTap(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactDirectoryRow extends StatelessWidget {
  final ContactDirectoryEntry entry;
  final Color accent;
  final VoidCallback onTap;

  const _ContactDirectoryRow({
    required this.entry,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.person_outline,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.contact.isNotEmpty ? entry.contact : 'No contact number',
                      style: TextStyle(
                        fontSize: 12,
                        color: entry.contact.isNotEmpty
                            ? context.fomraTextSecondary
                            : context.fomraTextSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${entry.leads.length} lead${entry.leads.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              ContactCallWhatsAppCompact(contact: entry.contact, accent: accent),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: context.fomraTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
