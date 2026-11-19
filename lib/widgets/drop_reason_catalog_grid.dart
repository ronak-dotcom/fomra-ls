import 'package:flutter/material.dart';

import '../models/lead_drop_reason.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_layout.dart';
import '../theme/fomra_theme_context.dart';

/// Translates "drop the item at [from] onto slot [to]" into the `newIndex` that
/// [LeadDropReasonCatalogService.reorder] (and [ReorderableListView]) expect —
/// an insert position measured *before* the dragged item is removed.
///
/// Dragging right shifts everything left by one once the item lifts out, so the
/// target slot has to be nudged up to land where the user actually dropped it.
int dropReasonReorderNewIndex(int from, int to) => to > from ? to + 1 : to;

/// Responsive card grid for the drop-reason catalog: 3 columns on desktop,
/// 2 on tablet, 1 on mobile, with drag-and-drop reordering.
///
/// Presentation only — every callback maps straight onto the existing catalog
/// service, so the CRUD, ids/slugs and persistence are untouched.
class DropReasonCatalogGrid extends StatefulWidget {
  final List<LeadDropReason> reasons;

  /// Called with the same (oldIndex, newIndex) convention the catalog service
  /// already uses.
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(LeadDropReason reason) onEdit;

  /// Hides the reason from new drops (leads already dropped keep it).
  final void Function(LeadDropReason reason) onDelete;

  /// Dropped leads using the reason; when given, shown on the card instead
  /// of the internal id, and tapping it calls [onOpenLeads].
  final int Function(LeadDropReason reason)? countOf;
  final void Function(LeadDropReason reason)? onOpenLeads;

  const DropReasonCatalogGrid({
    super.key,
    required this.reasons,
    required this.onReorder,
    required this.onEdit,
    required this.onDelete,
    this.countOf,
    this.onOpenLeads,
  });

  static const _gap = 14.0;

  @override
  State<DropReasonCatalogGrid> createState() => _DropReasonCatalogGridState();
}

class _DropReasonCatalogGridState extends State<DropReasonCatalogGrid> {
  int? _draggingIndex;

  int _columnsFor(double width) {
    if (width >= FomraLayout.desktopBreakpoint) return 3;
    if (width >= FomraLayout.tabletBreakpoint) return 2;
    return 1;
  }

  void _move(int from, int to) {
    if (from == to) return;
    widget.onReorder(from, dropReasonReorderNewIndex(from, to));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        final totalGap = DropReasonCatalogGrid._gap * (columns - 1);
        final cardWidth = (constraints.maxWidth - totalGap) / columns;

        return Wrap(
          spacing: DropReasonCatalogGrid._gap,
          runSpacing: DropReasonCatalogGrid._gap,
          children: [
            for (var i = 0; i < widget.reasons.length; i++)
              SizedBox(
                width: cardWidth,
                child: DragTarget<int>(
                  onWillAcceptWithDetails: (details) => details.data != i,
                  onAcceptWithDetails: (details) => _move(details.data, i),
                  builder: (context, candidate, rejected) => _ReasonCard(
                    key: ValueKey(widget.reasons[i].id),
                    reason: widget.reasons[i],
                    index: i,
                    cardWidth: cardWidth,
                    isDropTarget: candidate.isNotEmpty,
                    isDragging: _draggingIndex == i,
                    onEdit: () => widget.onEdit(widget.reasons[i]),
                    onDelete: () => widget.onDelete(widget.reasons[i]),
                    count: widget.countOf?.call(widget.reasons[i]),
                    onOpenLeads: widget.onOpenLeads == null
                        ? null
                        : () => widget.onOpenLeads!(widget.reasons[i]),
                    onDragStarted: () => setState(() => _draggingIndex = i),
                    onDragEnded: () => setState(() => _draggingIndex = null),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReasonCard extends StatefulWidget {
  final LeadDropReason reason;
  final int index;
  final double cardWidth;
  final bool isDropTarget;
  final bool isDragging;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final int? count;
  final VoidCallback? onOpenLeads;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  const _ReasonCard({
    super.key,
    required this.reason,
    required this.index,
    required this.cardWidth,
    required this.isDropTarget,
    required this.isDragging,
    required this.onEdit,
    required this.onDelete,
    this.count,
    this.onOpenLeads,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  @override
  State<_ReasonCard> createState() => _ReasonCardState();
}

class _ReasonCardState extends State<_ReasonCard> {
  static const _radius = 18.0;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lifted = _hovered || widget.isDropTarget;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        duration: AppMotion.fast,
        opacity: widget.isDragging ? 0.4 : 1,
        child: AnimatedContainer(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          // Rises slightly on hover, and the drop target gets the accent border
          // so it's obvious where the card will land.
          transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: context.fomraSurface,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(
              color: widget.isDropTarget
                  ? AppColors.primary
                  : lifted
                      ? AppColors.primary.withValues(alpha: 0.35)
                      : context.fomraBorder,
              width: widget.isDropTarget ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: lifted ? 0.10 : 0.04),
                blurRadius: lifted ? 18 : 10,
                offset: Offset(0, lifted ? 6 : 2),
              ),
            ],
          ),
          child: _body(context),
        ),
      ),
    );
  }

  /// [draggable] is false for the drag preview: its handle must be a plain icon,
  /// since a Draggable's feedback is built eagerly and a nested one would
  /// recurse forever.
  Widget _body(BuildContext context, {bool draggable = true}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.label_off_outlined,
                  size: 18,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.reason.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.fomraTextPrimary,
                    ),
                  ),
                ),
              ),
              draggable ? _dragHandle(context) : _handleIcon(context),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                  child: widget.count == null
                      ? _slugChip(context)
                      : _countChip(context, widget.count!)),
              const Spacer(),
              _action(
                context,
                icon: Icons.edit_outlined,
                tooltip: 'Edit',
                onTap: widget.onEdit,
              ),
              _action(
                context,
                icon: Icons.visibility_off_outlined,
                tooltip: 'Hide from new drops',
                color: AppColors.error,
                onTap: widget.onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "31 leads" — dropped leads with this reason; tap to open them.
  Widget _countChip(BuildContext context, int count) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: count == 0
            ? context.fomraSurfaceVar
            : AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: count == 0
                ? context.fomraBorder
                : AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(
        count == 1 ? '1 dropped lead' : '$count dropped leads',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: count == 0 ? context.fomraTextTertiary : AppColors.error,
        ),
      ),
    );
    if (count == 0 || widget.onOpenLeads == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: widget.onOpenLeads,
      child: chip,
    );
  }

  /// The slug is what every stored lead references, so it's shown verbatim.
  Widget _slugChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.fomraSurfaceVar,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.fomraBorder),
      ),
      child: Text(
        widget.reason.id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: context.fomraTextSecondary,
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      icon: Icon(icon, color: color ?? context.fomraTextSecondary),
    );
  }

  Widget _handleIcon(BuildContext context) => Icon(
        Icons.drag_indicator_rounded,
        size: 20,
        color: context.fomraTextTertiary,
      );

  Widget _dragHandle(BuildContext context) {
    final handle = _handleIcon(context);

    return Draggable<int>(
      data: widget.index,
      onDragStarted: widget.onDragStarted,
      onDragEnd: (_) => widget.onDragEnded(),
      onDraggableCanceled: (_, __) => widget.onDragEnded(),
      // Drag the card itself, not just the grip, so the whole thing follows the
      // pointer the way a card is expected to.
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: widget.cardWidth,
          child: Opacity(
            opacity: 0.95,
            child: Container(
              decoration: BoxDecoration(
                color: context.fomraSurface,
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: AppColors.primary, width: 1.6),
                boxShadow: AppColors.elevatedShadow,
              ),
              child: _body(context, draggable: false),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: handle),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(message: 'Drag to reorder', child: handle),
      ),
    );
  }
}
