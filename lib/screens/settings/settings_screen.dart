import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/lead_drop_reason.dart';
import '../../services/auth_service.dart';
import '../../services/lead_drop_reason_catalog_service.dart';
import '../../widgets/drop_reason_catalog_grid.dart';
import '../../services/role_access.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_layout.dart';
import '../../theme/fomra_theme_context.dart';
import '../../widgets/fomra_app_bar.dart';
import '../../widgets/fomra_app_shell.dart';
import '../../widgets/fomra_breadcrumb.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/change_password_section.dart';
import '../../widgets/portal_page_layout.dart';
import '../audit/audit_trail_screen.dart';
import '../employee_management/employee_management_portal_screen.dart';
import 'employee_monthly_targets_page.dart';
import 'error_log_page.dart';
import 'feature_controls_page.dart';
import 'monthly_targets_management_page.dart';
import '../../services/csv_saver_stub.dart'
    if (dart.library.html) '../../services/csv_saver_web.dart'
    if (dart.library.io) '../../services/csv_saver_io.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isManagement = AuthService.instance.isManagement;
    final canViewAudit = isManagement && RoleAccess.canViewAudit;

    return FomraAppShell(
      currentRoute: '/settings',
      appBar: const FomraAppBar(
        moduleName: 'Settings',
        showUniversalSearch: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            isManagement ? 'Management Settings' : 'Settings',
            style: TextStyle(
              fontSize: FomraLayout.responsiveClamp(
                context,
                min: 20,
                max: 22,
              ),
              fontWeight: FontWeight.w800,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isManagement
                ? 'Workspace controls, approval catalogs, and administrative tools.'
                : 'Manage account options and set your monthly targets.',
            style: TextStyle(
              fontSize: 13,
              color: context.fomraTextSecondary,
            ),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              // Four tiles per row (two on a narrow phone).
              final cols = c.maxWidth < 460 ? 2 : 4;
              final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
              final tiles = <Widget>[
              _SettingsTile(
                icon: Icons.lock_outline,
                label: 'Reset Password',
                accent: AppColors.purple,
                onTap: () => showResetPasswordDialog(context),
              ),
              // Employees propose their own monthly targets for approval.
              if (!isManagement)
                _SettingsTile(
                  icon: Icons.flag_outlined,
                  label: 'Set Monthly Targets',
                  accent: AppColors.warning,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EmployeeMonthlyTargetsPage(),
                    ),
                  ),
                ),
              if (isManagement)
                _SettingsTile(
                  icon: Icons.tune_rounded,
                  label: 'Feature Controls',
                  accent: AppColors.info,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FeatureControlsPage(),
                    ),
                  ),
                ),
              if (isManagement)
                _SettingsTile(
                  icon: Icons.flag_outlined,
                  label: 'Monthly Targets',
                  accent: AppColors.warning,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MonthlyTargetsManagementPage(),
                    ),
                  ),
                ),
              if (isManagement)
                _SettingsTile(
                  icon: Icons.groups_outlined,
                  label: 'User Management',
                  accent: AppColors.secondary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UserManagementPage(),
                    ),
                  ),
                ),
              if (canViewAudit)
                _SettingsTile(
                  icon: Icons.history_edu_outlined,
                  label: 'Audit Trail',
                  accent: AppColors.info,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const AuditTrailScreen(asSettingsChild: true),
                    ),
                  ),
                ),
              if (canViewAudit)
                _SettingsTile(
                  icon: Icons.bug_report_outlined,
                  label: 'Error Log',
                  accent: AppColors.error,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ErrorLogPage()),
                  ),
                ),
              if (isManagement)
                _SettingsTile(
                  icon: Icons.cancel_schedule_send_outlined,
                  label: 'Dropped Reasons',
                  accent: AppColors.error,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _DroppedReasonsPage(),
                    ),
                  ),
                ),
              if (isManagement)
                _SettingsTile(
                  icon: Icons.file_upload_outlined,
                  label: 'Bulk Lead Import',
                  accent: AppColors.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _BulkLeadImportPage(),
                    ),
                  ),
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final t in tiles) SizedBox(width: tileW, child: t),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        widget.accent.withValues(alpha: _hovered ? 0.45 : 0.25);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 420;
    // Width is controlled by the parent grid cell; fill it.
    const tileWidth = double.infinity;
    final tileHeight = compact ? 84.0 : 118.0;
    final tilePadding = compact ? 8.0 : 14.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: tileWidth,
          height: tileHeight,
          padding: EdgeInsets.all(tilePadding),
          decoration: BoxDecoration(
            color: context.fomraSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: _hovered ? 1.5 : 1),
            boxShadow: _hovered ? context.fomraCardShadow : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: compact ? 32 : 38,
                height: compact ? 32 : 38,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  color: widget.accent,
                  size: compact ? 17 : 20,
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 11.5 : 13,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: compact ? 12 : 14,
                    color: context.fomraTextSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DroppedReasonsPage extends StatefulWidget {
  const _DroppedReasonsPage();

  @override
  State<_DroppedReasonsPage> createState() => _DroppedReasonsPageState();
}

class _DroppedReasonsPageState extends State<_DroppedReasonsPage> {
  LeadDropReasonCatalogService get _catalog =>
      LeadDropReasonCatalogService.instance;

  @override
  void initState() {
    super.initState();
    _catalog.addListener(_rebuild);
  }

  @override
  void dispose() {
    _catalog.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _editReason({LeadDropReason? reason}) async {
    final controller = TextEditingController(text: reason?.label ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reason == null ? 'Add drop reason' : 'Edit drop reason'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Reason label',
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null || saved.trim().isEmpty) return;
    if (reason == null) {
      await _catalog.addReason(saved);
    } else {
      await _catalog.updateReason(reason.id, saved);
    }
  }

  /// Delete used to sit behind a two-step popup menu; on a card it's a single
  /// tap, so confirm before removing a reason leads may already reference.
  Future<void> _confirmDelete(LeadDropReason reason) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete drop reason?'),
        content: Text(
          '"${reason.label}" will no longer be offered when dropping a lead. '
          'Leads already dropped for this reason keep it on their record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _catalog.deleteReason(reason.id);
  }

  @override
  Widget build(BuildContext context) {
    final reasons = _catalog.current;
    return FomraAppShell(
      currentRoute: '/settings',
      appBar: FomraSubPageAppBar(
        title: 'Dropped Reasons',
        breadcrumbs: FomraBreadcrumbs.forSettingsChild('Dropped Reasons'),
      ),
      backgroundColor: context.fomraPageBg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SectionHeader(
            title: 'Dropped Reasons',
            subtitle: 'Add, edit, delete, and reorder the drop catalog used everywhere.',
            icon: Icons.cancel_schedule_send_outlined,
            trailing: TextButton.icon(
              onPressed: () => _editReason(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add reason'),
            ),
          ),
          const SizedBox(height: 16),
          DropReasonCatalogGrid(
            reasons: reasons,
            onReorder: _catalog.reorder,
            onEdit: (reason) => _editReason(reason: reason),
            onDelete: _confirmDelete,
          ),
        ],
      ),
    );
  }
}

/// Columns for the downloadable bulk-import template. Latitude/Longitude are
/// intentionally omitted — coordinates are derived from the Google Maps Link
/// during import (backend pipeline, not built here).
const _bulkImportColumns = <String>[
  'Owner',
  'Mobile',
  'Broker',
  'Village',
  'District',
  'Survey No',
  'Google Maps Link',
  'Land Extent',
  'Unit',
  'Terms',
  'Stage',
];

class _BulkLeadImportPage extends StatefulWidget {
  const _BulkLeadImportPage();

  @override
  State<_BulkLeadImportPage> createState() => _BulkLeadImportPageState();
}

class _BulkLeadImportPageState extends State<_BulkLeadImportPage> {
  String? _pickedFileName;

  String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String _csvRow(List<String> cells) => cells.map(_csvField).join(',');

  Future<void> _downloadTemplate() async {
    final example = [
      'John Doe',
      '9876543210',
      'Broker Name',
      'Village Name',
      'District Name',
      '123/4A',
      'https://maps.google.com/?q=13.0827,80.2707',
      '2.5',
      'Acre',
      'Outright Purchase',
      'Negotiation',
    ];
    final csv = '${_csvRow(_bulkImportColumns)}\r\n${_csvRow(example)}\r\n';
    final bytes = Uint8List.fromList(utf8.encode(csv));
    try {
      await saveCsv(bytes, 'FomraLandIQ_Bulk_Lead_Import_Template.csv');
      if (mounted) {
        AppFeedback.success(context, 'Template downloaded');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Could not download template: $e');
      }
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'csv'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _pickedFileName = result.files.first.name);
    if (mounted) {
      AppFeedback.info(
        context,
        'File selected. Parsing & import will be enabled with the backend pipeline.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FomraAppShell(
      currentRoute: '/settings',
      appBar: FomraSubPageAppBar(
        title: 'Bulk Lead Import',
        breadcrumbs: FomraBreadcrumbs.forSettingsChild('Bulk Lead Import'),
      ),
      backgroundColor: context.fomraPageBg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const SectionHeader(
            title: 'Bulk Lead Import',
            subtitle:
                'Download the template, fill it in, and upload to import leads in bulk.',
            icon: Icons.file_upload_outlined,
          ),
          const SizedBox(height: 12),
          _actionsCard(context),
          const SizedBox(height: 12),
          _previewCard(context),
          const SizedBox(height: 12),
          _infoCard(context),
          const SizedBox(height: 12),
          _guidelinesCard(context),
        ],
      ),
    );
  }

  Widget _actionsCard(BuildContext context) {
    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Get started',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.fomraTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Use the official template so every column maps to the right field.',
            style: TextStyle(fontSize: 12, color: context.fomraTextSecondary),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final download = OutlinedButton.icon(
                onPressed: _downloadTemplate,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download Excel Template'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              );
              final upload = FilledButton.icon(
                onPressed: _uploadFile,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Upload Excel File'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              );
              if (c.maxWidth < 460) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [download, const SizedBox(height: 10), upload],
                );
              }
              return Row(
                children: [
                  Expanded(child: download),
                  const SizedBox(width: 12),
                  Expanded(child: upload),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _previewCard(BuildContext context) {
    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Preview',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.fomraTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.fomraSurfaceVar.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.fomraBorder,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  _pickedFileName == null
                      ? Icons.table_chart_outlined
                      : Icons.description_outlined,
                  size: 32,
                  color: context.fomraTextSecondary,
                ),
                const SizedBox(height: 10),
                Text(
                  _pickedFileName == null
                      ? 'No file selected yet'
                      : _pickedFileName!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.fomraTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _pickedFileName == null
                      ? 'Upload a completed template to see a row-by-row preview here.'
                      : 'Row-by-row validation and preview will appear here once the import pipeline is connected.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.fomraTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(BuildContext context) {
    final rows = <(IconData, String, String)>[
      (
        Icons.link_rounded,
        'Google Maps Link',
        'Paste only the Google Maps property link — latitude & longitude are extracted automatically into the existing coordinate fields.'
      ),
      (
        Icons.place_outlined,
        'No Lat/Long columns',
        'You never type coordinates. The template deliberately omits Latitude & Longitude.'
      ),
      (
        Icons.tag_rounded,
        'Automatic Lead IDs',
        'Lead IDs are generated on import — imported leads appear across Project Map, Land Workspace, Search, Reports, Dashboard and Analytics.'
      ),
    ];
    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: AppColors.info),
              const SizedBox(width: 8),
              Text(
                'Import information',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.fomraTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(r.$1, size: 18, color: context.fomraTextSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.$3,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _guidelinesCard(BuildContext context) {
    final guidelines = <String>[
      'Use the downloaded template columns exactly: ${_bulkImportColumns.join(', ')}.',
      'Land Extent must be a number only; put the unit (Acre / Ground / Cent / Sq Ft) in the Unit column.',
      'Terms must be one of: Outright Purchase, Joint Venture, Marketing, Deferred Payment.',
      'Google Maps Link must be a valid property link — rows with an invalid or unreadable link are marked Invalid and skipped.',
      'Do not add Latitude or Longitude columns — coordinates are extracted from the link automatically.',
    ];
    return AppCard(
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rule_rounded, size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                'Import guidelines',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.fomraTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final g in guidelines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      g,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
