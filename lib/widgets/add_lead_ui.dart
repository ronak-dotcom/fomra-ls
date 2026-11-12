import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../config/maptiler_tiles.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import '../utils/reverse_geocode.dart';
import 'map_layer_toggle.dart';
import 'lead_map_controls.dart';

/// Design tokens for the Add Land Lead enterprise form.
abstract final class AddLeadUi {
  static const pageBg = Color(0xFFF8FAFC);
  static const cardBorder = Color(0xFFE5E7EB);
  static const sectionGap = 20.0;
  static const fieldGap = 12.0;
  static const fieldHeight = 48.0;
  static const fieldRadius = 14.0;
  static const cardRadius = 20.0;
  static const motion = Duration(milliseconds: 200);
  static const curve = Curves.easeInOut;

  static List<BoxShadow> cardShadow([bool hovered = false]) => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: hovered ? 0.1 : 0.06),
          blurRadius: hovered ? 20 : 16,
          offset: Offset(0, hovered ? 6 : 4),
        ),
      ];
}

// ── App bar ─────────────────────────────────────────────────────────────────

class AddLeadAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool saving;

  const AddLeadAppBar({
    super.key,
    required this.title,
    this.saving = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? context.fomraSurface : Colors.white;

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: kToolbarHeight,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AddLeadUi.cardBorder)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                tooltip: 'Back',
                onPressed: saving ? null : () => Navigator.maybePop(context),
                style: IconButton.styleFrom(
                  foregroundColor: context.fomraTextPrimary,
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: context.fomraTextPrimary,
                  ),
                ),
              ),
              // Save lives only in the sticky footer at the bottom now.
            ],
          ),
        ),
      ),
    );
  }
}

// ── Progress navigation ───────────────────────────────────────────────────────

class AddLeadProgressStep {
  final String label;
  final bool completed;
  final bool active;

  const AddLeadProgressStep({
    required this.label,
    required this.completed,
    required this.active,
  });
}

class AddLeadProgressNav extends StatelessWidget {
  final List<AddLeadProgressStep> steps;
  final ValueChanged<int> onStepTap;

  const AddLeadProgressNav({
    super.key,
    required this.steps,
    required this.onStepTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? context.fomraSurface : Colors.white;

    return Material(
      color: bg,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AddLeadUi.cardBorder)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: context.fomraTextSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                _ProgressChip(
                  index: i,
                  step: steps[i],
                  onTap: () => onStepTap(i),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressChip extends StatefulWidget {
  final int index;
  final AddLeadProgressStep step;
  final VoidCallback onTap;

  const _ProgressChip({
    required this.index,
    required this.step,
    required this.onTap,
  });

  @override
  State<_ProgressChip> createState() => _ProgressChipState();
}

class _ProgressChipState extends State<_ProgressChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.step.active;
    final done = widget.step.completed;
    final bg = active
        ? AppColors.primary.withValues(alpha: 0.1)
        : _hovered
            ? const Color(0xFFF1F5F9)
            : Colors.transparent;
    final border = active
        ? AppColors.primary.withValues(alpha: 0.35)
        : AddLeadUi.cardBorder.withValues(alpha: 0.8);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AddLeadUi.motion,
          curve: AddLeadUi.curve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: AddLeadUi.motion,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.success
                      : active
                          ? AppColors.primary
                          : const Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : Text(
                        '${widget.index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : context.fomraTextSecondary,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.step.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? AppColors.primary : context.fomraTextPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class AddLeadSectionCard extends StatefulWidget {
  final String number;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final bool compact;

  const AddLeadSectionCard({
    super.key,
    required this.number,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    required this.child,
    this.compact = false,
  });

  @override
  State<AddLeadSectionCard> createState() => _AddLeadSectionCardState();
}

class _AddLeadSectionCardState extends State<AddLeadSectionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? context.fomraSurface : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AddLeadUi.motion,
        curve: AddLeadUi.curve,
        transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(AddLeadUi.cardRadius),
          border: const Border.fromBorderSide(
            BorderSide(color: AddLeadUi.cardBorder),
          ),
          boxShadow: AddLeadUi.cardShadow(_hovered),
        ),
        padding: EdgeInsets.all(widget.compact ? 16 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              number: widget.number,
              title: widget.title,
              subtitle: widget.subtitle,
              icon: widget.icon,
              trailing: widget.trailing,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: AddLeadUi.cardBorder),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String number;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  const _SectionHeader({
    required this.number,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: context.fomraTextPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: context.fomraTextSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (icon != null)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

/// Small pill shown in a section header's trailing slot, e.g. to indicate a
/// value will be generated automatically rather than entered by the user.
class AddLeadHeaderTag extends StatelessWidget {
  final String label;
  final String? tooltip;

  const AddLeadHeaderTag({super.key, required this.label, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
    if (tooltip == null) return pill;
    return Tooltip(message: tooltip!, child: pill);
  }
}

// ── Form layout helpers ───────────────────────────────────────────────────────

Widget addLeadFormRow(BuildContext context, Widget left, Widget right) {
  final wide = MediaQuery.sizeOf(context).width >= 720;
  if (!wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        left,
        const SizedBox(height: AddLeadUi.fieldGap),
        right,
      ],
    );
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: AddLeadUi.fieldGap),
      Expanded(child: right),
    ],
  );
}

Widget addLeadFieldIcon(IconData icon, {Color? color}) {
  final c = color ?? AppColors.primary;
  return Padding(
    padding: const EdgeInsets.only(left: 10, right: 2),
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: c),
    ),
  );
}

InputDecoration addLeadInputDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  IconData? icon,
  bool required = false,
  int maxLines = 1,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final fill = isDark ? context.fomraSurfaceVar : Colors.white;

  OutlineInputBorder border([Color? c, double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AddLeadUi.fieldRadius),
        borderSide: BorderSide(color: c ?? AddLeadUi.cardBorder, width: w),
      );

  return InputDecoration(
    labelText: label != null ? label + (required ? ' *' : '') : null,
    hintText: hint,
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    isDense: true,
    filled: true,
    fillColor: fill,
    prefixIcon: icon != null ? addLeadFieldIcon(icon) : null,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: maxLines > 1 ? 14 : 13,
    ),
    border: border(),
    enabledBorder: border(),
    focusedBorder: border(AppColors.primary, 1.5),
    errorBorder: border(AppColors.error),
    focusedErrorBorder: border(AppColors.error, 1.5),
  );
}

// ── Sticky footer ─────────────────────────────────────────────────────────────

class AddLeadStickyFooter extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final bool saving;
  /// Whether all mandatory fields are currently filled in. When false the
  /// Save button is dimmed as a visual cue, but stays tappable — pressing it
  /// still runs validation, which scrolls to and highlights what's missing
  /// instead of doing nothing.
  final bool enabled;

  const AddLeadStickyFooter({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.saving = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            border: const Border(top: BorderSide(color: AddLeadUi.cardBorder)),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    side: const BorderSide(color: AddLeadUi.cardBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: saving ? null : onSave,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: enabled
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Lead',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Segmented control ─────────────────────────────────────────────────────────

enum AddLeadLocationMode { manual, live }

class AddLeadLocationSegment extends StatelessWidget {
  final AddLeadLocationMode mode;
  final ValueChanged<AddLeadLocationMode> onChanged;

  const AddLeadLocationSegment({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AddLeadUi.cardBorder),
      ),
      child: Row(
        children: [
          _seg(context, 'Manual', Icons.edit_outlined, AddLeadLocationMode.manual),
          _seg(context, 'Live GPS', Icons.gps_fixed_rounded, AddLeadLocationMode.live),
        ],
      ),
    );
  }

  Widget _seg(
    BuildContext context,
    String label,
    IconData icon,
    AddLeadLocationMode value,
  ) {
    final active = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: AddLeadUi.motion,
          curve: AddLeadUi.curve,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? AppColors.primary : context.fomraTextSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColors.primary : context.fomraTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Location search ───────────────────────────────────────────────────────────

class AddLeadLocationSearch extends StatefulWidget {
  final ValueChanged<LatLng> onSelected;

  const AddLeadLocationSearch({super.key, required this.onSelected});

  @override
  State<AddLeadLocationSearch> createState() => _AddLeadLocationSearchState();
}

class _AddLeadLocationSearchState extends State<AddLeadLocationSearch> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  String? _error;
  List<LocationSearchHit> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _suggestLocations(query);
    });
  }

  Future<void> _suggestLocations(String query) async {
    if (query.isEmpty) return;

    try {
      final hits = await searchLocations(
        query,
        limit: 8,
        appendRegionBias: false,
      );
      if (!mounted || _ctrl.text.trim() != query) return;
      setState(() {
        _results = hits;
        _error = null;
      });
    } catch (_) {
      // Silent for live suggestions — Go button surfaces hard errors.
    }
  }

  Future<void> _search() async {
    _debounce?.cancel();
    final query = _ctrl.text.trim();
    if (query.isEmpty || _searching) return;

    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });

    try {
      final hits = await searchLocations(query);
      if (!mounted) return;
      setState(() {
        _results = hits;
        if (hits.isEmpty) {
          _error = 'No locations found. Try village, area, or pincode.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Search failed. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(LocationSearchHit hit) {
    _debounce?.cancel();
    setState(() {
      _results = [];
      _error = null;
      _ctrl.text = hit.displayName.split(',').first.trim();
    });
    widget.onSelected(LatLng(hit.lat, hit.lng));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  labelText: 'Search location',
                  hintText: 'Village, area, landmark, pincode…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: context.fomraSurfaceVar.withValues(alpha: 0.55),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AddLeadUi.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AddLeadUi.cardBorder),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _searching ? null : _search,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _searching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Go'),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: TextStyle(
              fontSize: 11,
              color: context.fomraTextSecondary,
            ),
          ),
        ],
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              border: Border.all(color: AddLeadUi.cardBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: AddLeadUi.cardBorder,
              ),
              itemBuilder: (context, i) {
                final hit = _results[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.place_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    hit.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => _pick(hit),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// ── Map section ───────────────────────────────────────────────────────────────

class AddLeadMapPicker extends StatefulWidget {
  final MapController mapController;
  final LatLng defaultCenter;
  final LatLng? pinnedPoint;
  final bool resolving;
  final bool fetchingMyLocation;
  final String? status;
  final VoidCallback onMapReady;

  /// Leave null for a read-only map: the pin can then only be placed by the
  /// caller (live GPS capture), never by tapping. Add Lead uses this — typed
  /// coordinates and map pins are rejected there, so the displayed pin always
  /// matches the captured GPS.
  final Future<void> Function(LatLng)? onTap;

  /// Leave null to hide the "My Location" button.
  final Future<void> Function()? onMyLocation;

  const AddLeadMapPicker({
    super.key,
    required this.mapController,
    required this.defaultCenter,
    required this.pinnedPoint,
    required this.resolving,
    this.fetchingMyLocation = false,
    this.status,
    required this.onMapReady,
    this.onTap,
    this.onMyLocation,
  });

  @override
  State<AddLeadMapPicker> createState() => _AddLeadMapPickerState();
}

class _AddLeadMapPickerState extends State<AddLeadMapPicker> {
  bool _satelliteLayer = false;

  bool get _readOnly => widget.onTap == null;

  @override
  Widget build(BuildContext context) {
    final mapController = widget.mapController;
    final defaultCenter = widget.defaultCenter;
    final pinnedPoint = widget.pinnedPoint;
    final resolving = widget.resolving;
    final fetchingMyLocation = widget.fetchingMyLocation;
    final onMapReady = widget.onMapReady;
    final onTap = widget.onTap;
    final onMyLocation = widget.onMyLocation;
    // The "tap to drop a pin" hint would be a lie on a read-only map.
    final showHint = !_readOnly && pinnedPoint == null && !resolving;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AddLeadUi.cardBorder),
        boxShadow: AddLeadUi.cardShadow(),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 280,
        child: Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: pinnedPoint ?? defaultCenter,
                initialZoom: pinnedPoint != null ? 16 : 11,
                onMapReady: onMapReady,
                onTap: _readOnly ? null : (_, point) => onTap!(point),
                // Still pan/zoom on a read-only map — only pin placement goes.
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom,
                ),
              ),
              children: [
                MapTilerTiles.tileLayer(
                  urlTemplate:
                      MapTilerTiles.urlFor(satelliteLayer: _satelliteLayer),
                  satelliteLayer: _satelliteLayer,
                ),
                if (pinnedPoint != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: pinnedPoint,
                      width: 40,
                      height: 48,
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFFE53935),
                        size: 40,
                      ),
                    ),
                  ]),
              ],
            ),
            Positioned(
              right: 12,
              top: 12,
              child: MapLayerToggle(
                satellite: _satelliteLayer,
                onChanged: (v) => setState(() => _satelliteLayer = v),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: MapZoomControls(
                controller: mapController,
                onExpand: () => showFullscreenLeadMap(
                  context,
                  initialCenter: pinnedPoint ?? defaultCenter,
                  initialZoom: pinnedPoint != null ? 16 : 11,
                  pinnedPoint: pinnedPoint,
                  onTap: _readOnly ? null : onTap,
                  title: 'Pin Location',
                ),
              ),
            ),
            if (showHint)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AddLeadUi.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 16,
                        color: AppColors.primary.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tap the map to drop a pin — location details fill automatically',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: context.fomraTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (onMyLocation != null)
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                elevation: 3,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: InkWell(
                  onTap: fetchingMyLocation || resolving ? null : onMyLocation,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (fetchingMyLocation)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const Icon(Icons.my_location_rounded, size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        const Text(
                          'My Location',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (resolving)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Live location card ────────────────────────────────────────────────────────

class AddLeadLiveLocationCard extends StatelessWidget {
  final bool fetching;
  final String? status;
  final VoidCallback? onTap;

  const AddLeadLiveLocationCard({
    super.key,
    required this.fetching,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final filled = status != null && status!.contains('✓');

    return Material(
      // Follows dark mode instead of a hardcoded white bar.
      color: context.isDarkMode ? context.fomraSurfaceVar : Colors.white,
      borderRadius: BorderRadius.circular(AddLeadUi.fieldRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AddLeadUi.fieldRadius),
        child: Container(
          height: AddLeadUi.fieldHeight + 8,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AddLeadUi.fieldRadius),
            border: Border.all(
              color: filled
                  ? AppColors.success.withValues(alpha: 0.45)
                  : AddLeadUi.cardBorder,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: (filled ? AppColors.success : AppColors.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: fetching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        filled ? Icons.location_on_rounded : Icons.gps_fixed_rounded,
                        size: 18,
                        color: filled ? AppColors.success : AppColors.primary,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  fetching
                      ? 'Getting live location…'
                      : filled
                          ? 'Location captured'
                          : 'Capture live GPS location',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: filled ? AppColors.success : context.fomraTextPrimary,
                  ),
                ),
              ),
              if (!fetching)
                Icon(
                  filled ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                  size: 18,
                  color: filled ? AppColors.success : context.fomraTextSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Save loading overlay ──────────────────────────────────────────────────────

class AddLeadSaveOverlay extends StatelessWidget {
  final String message;

  const AddLeadSaveOverlay({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Material(
              color: context.fomraSurface,
              borderRadius: BorderRadius.circular(20),
              elevation: 12,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.fomraTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Please wait…',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.fomraTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Photo upload ──────────────────────────────────────────────────────────────

class AddLeadPhotoDraft {
  final Uint8List bytes;
  final String name;
  final int originalSize;

  const AddLeadPhotoDraft({
    required this.bytes,
    required this.name,
    required this.originalSize,
  });
}

class AddLeadPhotoUpload extends StatefulWidget {
  final List<String> existingPhotoUrls;
  final List<AddLeadPhotoDraft> photos;
  final int maxPhotos;
  final bool compressing;
  final bool cameraOnly;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;
  final ValueChanged<int>? onRemoveExisting;

  const AddLeadPhotoUpload({
    super.key,
    this.existingPhotoUrls = const [],
    required this.photos,
    required this.maxPhotos,
    required this.compressing,
    this.cameraOnly = true,
    required this.onPick,
    required this.onRemove,
    this.onRemoveExisting,
  });

  @override
  State<AddLeadPhotoUpload> createState() => _AddLeadPhotoUploadState();
}

class _AddLeadPhotoUploadState extends State<AddLeadPhotoUpload> {
  bool _hoveringDrop = false;

  int get _total => widget.existingPhotoUrls.length + widget.photos.length;

  @override
  Widget build(BuildContext context) {
    final canAdd = _total < widget.maxPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.compressing) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Compressing photo…',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.fomraTextPrimary,
                        ),
                      ),
                      Text(
                        'Optimizing to 250 KB before preview',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.fomraTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_total > 0) ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < widget.existingPhotoUrls.length; i++)
                _thumb(
                  context,
                  Image.network(widget.existingPhotoUrls[i], fit: BoxFit.cover),
                  onRemove: widget.onRemoveExisting == null
                      ? null
                      : () => widget.onRemoveExisting!(i),
                ),
              for (var i = 0; i < widget.photos.length; i++)
                _thumb(
                  context,
                  Image.memory(widget.photos[i].bytes, fit: BoxFit.cover),
                  onRemove: () => widget.onRemove(i),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$_total of ${widget.maxPhotos} photos · max 250 KB each',
            style: TextStyle(fontSize: 11, color: context.fomraTextSecondary),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.compressing)
          _dropZone(
            context,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(height: 8),
                Text(
                  'Compressing photo to 250 KB…',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            onTap: null,
          )
        else if (canAdd)
          _dropZone(
            context,
            onTap: widget.onPick,
            prominent: _total == 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo_camera_outlined,
                  size: _total == 0 ? 32 : 24,
                  color: AppColors.primary.withValues(alpha: 0.85),
                ),
                SizedBox(height: _total == 0 ? 10 : 6),
                Text(
                  _total == 0
                      ? (widget.cameraOnly
                          ? 'Tap to take a photo'
                          : 'Tap to add a photo')
                      : (widget.cameraOnly
                          ? 'Take another photo'
                          : 'Add another photo'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                if (_total == 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.cameraOnly
                        ? 'Camera only · up to ${widget.maxPhotos} photos'
                        : 'Camera or gallery · up to ${widget.maxPhotos} photos',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.fomraTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _thumb(BuildContext context, Widget image, {VoidCallback? onRemove}) {
    return Stack(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AddLeadUi.cardBorder),
            boxShadow: AddLeadUi.cardShadow(),
          ),
          clipBehavior: Clip.antiAlias,
          child: image,
        ),
        if (onRemove != null)
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dropZone(
    BuildContext context, {
    required Widget child,
    VoidCallback? onTap,
    bool prominent = false,
  }) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveringDrop = true),
      onExit: (_) => setState(() => _hoveringDrop = false),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AddLeadUi.motion,
          curve: AddLeadUi.curve,
          height: prominent ? 140 : 72,
          transform: Matrix4.translationValues(0, _hoveringDrop && onTap != null ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: _hoveringDrop && onTap != null
                ? AppColors.primary.withValues(alpha: 0.04)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hoveringDrop && onTap != null
                  ? AppColors.primary.withValues(alpha: 0.45)
                  : AddLeadUi.cardBorder,
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: AddLeadUi.cardBorder.withValues(
                alpha: _hoveringDrop && onTap != null ? 0.0 : 1.0,
              ),
              radius: 16,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        Radius.circular(radius),
      ));
    canvas.drawPath(
      _dashPath(path, dashArray: const [6, 4]),
      paint,
    );
  }

  Path _dashPath(Path source, {required List<double> dashArray}) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = dashArray[0];
        dashed.addPath(
          metric.extractPath(distance, distance + len),
          Offset.zero,
        );
        distance += len + dashArray[1];
      }
    }
    return dashed;
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ── Dropdown option row ───────────────────────────────────────────────────────

Widget addLeadDropdownRow({
  required IconData icon,
  required String label,
  required Color iconColor,
}) {
  return Row(
    children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: iconColor),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );
}
