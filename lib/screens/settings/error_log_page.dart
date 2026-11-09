import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/error_log_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/fomra_breadcrumb.dart';
import '../../widgets/portal_page_layout.dart';
import '../../widgets/ui/app_components.dart';

/// Settings → Error Log (management only): every error users hit — failed
/// logins, errors shown on screen, crashes — with who, when, which screen and
/// the underlying database/auth message.
class ErrorLogPage extends StatefulWidget {
  const ErrorLogPage({super.key});

  @override
  State<ErrorLogPage> createState() => _ErrorLogPageState();
}

class _ErrorLogPageState extends State<ErrorLogPage> {
  static const _sources = <String, String>{
    '': 'All',
    'login': 'Login',
    'shown_to_user': 'Shown on screen',
    'caught': 'Failed actions',
    'flutter': 'App errors',
    'uncaught': 'Crashes',
  };

  List<AppErrorLogEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _source = '';
  String? _user;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ErrorLogService.recent();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the error log: $e';
      });
    }
  }

  List<AppErrorLogEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    return _entries.where((e) {
      if (_source.isNotEmpty && e.source != _source) return false;
      if (_user != null && e.who != _user) return false;
      if (q.isEmpty) return true;
      return '${e.who} ${e.userEmail} ${e.action} ${e.screen} ${e.message} '
              '${e.details}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final users = {for (final e in _entries) e.who}.toList()..sort();
    final shown = _filtered;
    return FomraAppShell(
      currentRoute: '/settings',
      appBar: FomraSubPageAppBar(
        title: 'Error Log',
        breadcrumbs: FomraBreadcrumbs.forSettingsChild('Error Log'),
      ),
      backgroundColor: context.fomraPageBg,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            SectionHeader(
              title: 'Error Log',
              subtitle: 'Errors people hit in the app: failed logins, errors '
                  'shown on screen and crashes. Newest first (last 300).',
              icon: Icons.bug_report_outlined,
              trailing: IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                      hintText: 'Search message, screen, action',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                DropdownButton<String?>(
                  value: _user,
                  hint: const Text('All users'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('All users')),
                    for (final u in users)
                      DropdownMenuItem<String?>(value: u, child: Text(u)),
                  ],
                  onChanged: (v) => setState(() => _user = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in _sources.entries)
                  ChoiceChip(
                    label: Text(s.value),
                    selected: _source == s.key,
                    onSelected: (_) => setState(() => _source = s.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.error))
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _entries.isEmpty
                      ? 'No errors recorded yet.'
                      : 'No errors match these filters.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.fomraTextSecondary),
                ),
              )
            else
              for (final e in shown) _EntryCard(entry: e),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final AppErrorLogEntry entry;
  const _EntryCard({required this.entry});

  static final _fmt = DateFormat('d MMM yyyy, h:mm:ss a');

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final meta = [
      e.source.replaceAll('_', ' '),
      if (e.action.isNotEmpty) e.action,
      if (e.screen.isNotEmpty) e.screen,
      if (e.platform.isNotEmpty) e.platform,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: context.fomraSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.fomraBorder),
      ),
      child: ExpansionTile(
        shape: const Border(),
        leading: Icon(
          e.source == 'login'
              ? Icons.lock_outline_rounded
              : Icons.error_outline_rounded,
          color: AppColors.error,
        ),
        title: Text(
          e.message.isEmpty ? '(no message)' : e.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: context.fomraTextPrimary,
          ),
        ),
        subtitle: Text(
          '${e.who} · ${_fmt.format(e.createdAt)}\n$meta',
          style: TextStyle(fontSize: 11.5, color: context.fomraTextSecondary),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            e.fullText,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontFamily: 'monospace',
              color: context.fomraTextSecondary,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: e.fullText)),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy'),
            ),
          ),
        ],
      ),
    );
  }
}
