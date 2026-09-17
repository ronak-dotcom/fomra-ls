import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/land_lead.dart';
import '../../services/app_store.dart';
import '../../services/land_lead_legal_service.dart';
import '../../services/land_lead_signed_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fomra_theme_context.dart';
import '../../utils/image_compressor.dart';
import '../../widgets/ui/app_components.dart';
import '../../widgets/ui/app_feedback.dart';

/// "Project Signed" submission window: attach supporting photos/documents,
/// add a note, and submit for management approval. Images are compressed
/// before upload. The lead only becomes Signed once management approves.
class SignedProjectDialog extends StatefulWidget {
  final String leadId;

  const SignedProjectDialog({super.key, required this.leadId});

  @override
  State<SignedProjectDialog> createState() => _SignedProjectDialogState();
}

class _PickedFile {
  final Uint8List bytes;
  final String name;
  const _PickedFile({required this.bytes, required this.name});
}

class _SignedProjectDialogState extends State<SignedProjectDialog> {
  static const _maxFiles = 6;

  final _noteCtrl = TextEditingController();
  final List<_PickedFile> _files = [];
  bool _submitting = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  bool _isImage(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
  }

  String _jpegName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    return '$base.jpg';
  }

  Future<void> _pickFiles() async {
    if (_submitting) return;
    final remaining = _maxFiles - _files.length;
    if (remaining <= 0) {
      AppFeedback.warning(context, 'Maximum $_maxFiles files allowed');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files
        .where((f) => f.bytes != null && f.name.trim().isNotEmpty)
        .take(remaining)
        .map((f) => _PickedFile(bytes: f.bytes!, name: f.name))
        .toList();
    if (picked.isEmpty) return;
    setState(() => _files.addAll(picked));
  }

  Future<({Uint8List bytes, String name})> _prepare(_PickedFile file) async {
    if (_isImage(file.name)) {
      final compressed = await ImageCompressor.compressTo1Mb(file.bytes);
      return (bytes: compressed, name: _jpegName(file.name));
    }
    if (file.bytes.length > ImageCompressor.maxBytes1Mb) {
      throw Exception('${file.name} exceeds 1 MB. Use a smaller file.');
    }
    return (bytes: file.bytes, name: file.name);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final urls = <String>[];
      for (final file in _files) {
        final prepared = await _prepare(file);
        final doc = await LandLeadLegalService.uploadDocument(
          leadId: widget.leadId,
          bytes: prepared.bytes,
          fileName: prepared.name,
        );
        urls.add(doc.fileUrl);
      }
      await LandLeadSignedService.submit(
        leadId: widget.leadId,
        note: _noteCtrl.text,
        photoUrls: urls,
      );
      if (!mounted) return;
      await _showCelebration();
      if (!mounted) return;
      AppFeedback.success(context, 'Project Signed Request Submitted Successfully');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppFeedback.error(
          context, 'Could not submit: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _showCelebration() async {
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Project signed celebration',
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) => const _SignedCelebrationDialog(),
      transitionBuilder: (ctx, anim, sec, child) {
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return FadeTransition(opacity: fade, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: fomraDialogInset(context),
      backgroundColor: context.fomraSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: fomraDialogConstraints(context, maxWidth: 460, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: LeadStatus.signed.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.check_circle,
                        color: LeadStatus.signed.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Project Signed',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.fomraTextPrimary,
                          ),
                        ),
                        Text(
                          AppStore.instance.displayNameForLeadId(widget.leadId),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _submitting ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Attach the signed agreement photos/documents and submit for '
                'management approval. The lead becomes Signed only after approval.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.fomraTextSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Prominent tap-anywhere upload zone — reads clearly as a
                      // file drop area on mobile instead of a thin button.
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _submitting ? null : _pickFiles,
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: AppColors.purple.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.purple.withValues(alpha: 0.35),
                                width: 1.4,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 18),
                            child: Column(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: AppColors.purple
                                        .withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.cloud_upload_outlined,
                                      color: AppColors.purple, size: 24),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _files.isEmpty
                                      ? 'Upload documents / photos'
                                      : 'Add more (${_files.length}/$_maxFiles)',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.purple,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'PDF, JPG, PNG, DOC · images auto-compress',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.fomraTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_files.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        for (var i = 0; i < _files.length; i++)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(color: context.fomraBorder),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _isImage(_files[i].name)
                                      ? Icons.image_outlined
                                      : Icons.description_outlined,
                                  size: 18,
                                  color: AppColors.purple,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _files[i].name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.fomraTextPrimary,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _submitting
                                      ? null
                                      : () =>
                                          setState(() => _files.removeAt(i)),
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteCtrl,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 500,
                        decoration: InputDecoration(
                          labelText: 'Note (optional)',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor:
                              context.fomraSurfaceVar.withValues(alpha: 0.55),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: context.fomraBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: context.fomraBorder),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _submitting ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle, size: 18),
                    label: Text(_submitting ? 'Submitting…' : 'Project Signed'),
                    style: FilledButton.styleFrom(
                      backgroundColor: LeadStatus.signed.color,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                    ),
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

class _SignedCelebrationDialog extends StatefulWidget {
  const _SignedCelebrationDialog();

  @override
  State<_SignedCelebrationDialog> createState() => _SignedCelebrationDialogState();
}

class _SignedCelebrationDialogState extends State<_SignedCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _ConfettiPainter(progress: _controller.value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                decoration: BoxDecoration(
                  color: context.fomraSurface,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: AppColors.elevatedShadow,
                  border: Border.all(color: context.fomraBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: LeadStatus.signed.color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.celebration_rounded,
                        color: LeadStatus.signed.color,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Project Signed Request Submitted Successfully',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Awaiting management approval',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double progress;

  _ConfettiPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEC4899),
    ];
    const count = 22;
    for (var i = 0; i < count; i++) {
      final seed = i * 37;
      final x = ((seed % 100) / 100.0) * size.width;
      final y = (progress * size.height) + ((seed % 70) - 35);
      final sizeFactor = 4 + (seed % 4).toDouble();
      paint.color = colors[i % colors.length].withValues(
        alpha: (1 - progress).clamp(0.0, 1.0),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: sizeFactor, height: sizeFactor * 0.8),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
