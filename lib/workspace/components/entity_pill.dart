import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Polymorphic inline reference pill: `[DomainIcon + Title]`.
///
/// - Tap/Click: opens the referenced entity in the Peek Surface without
///   destroying the user's current context.
/// - Cmd/Ctrl + Click: switches the Primary Canvas to that lens.
/// - Desktop Hover (300ms): shows a compact 280px Hovercard with snippet/status,
///   one inline quick-action, and "Open in Peek".
class EntityPill extends ConsumerStatefulWidget {
  final WorkspaceEntityRef entity;
  final ValueChanged<WorkspaceEntityRef>? onSwitchLens;
  final ValueChanged<WorkspaceEntityRef>? onToggleTodo;

  const EntityPill({
    super.key,
    required this.entity,
    this.onSwitchLens,
    this.onToggleTodo,
  });

  @override
  ConsumerState<EntityPill> createState() => _EntityPillState();
}

class _EntityPillState extends ConsumerState<EntityPill> {
  final LayerLink _layerLink = LayerLink();
  Timer? _hoverTimer;
  OverlayEntry? _hoverEntry;
  bool _pointerInsideCard = false;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _removeHoverCard();
    super.dispose();
  }

  void _scheduleHoverCard() {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 300), _showHoverCard);
  }

  void _cancelHoverCard() {
    _hoverTimer?.cancel();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!_pointerInsideCard && mounted) {
        _removeHoverCard();
      }
    });
  }

  void _showHoverCard() {
    if (!mounted || _hoverEntry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _hoverEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        width: 280,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 28),
          child: MouseRegion(
            onEnter: (_) => _pointerInsideCard = true,
            onExit: (_) {
              _pointerInsideCard = false;
              _removeHoverCard();
            },
            child: _EntityHoverCard(
              entity: widget.entity,
              onOpenPeek: () {
                _removeHoverCard();
                ref.read(peekProvider.notifier).open(widget.entity);
              },
              onQuickAction: widget.entity.domain == WorkspaceDomain.todo
                  ? () {
                      _removeHoverCard();
                      widget.onToggleTodo?.call(widget.entity);
                    }
                  : null,
            ),
          ),
        ),
      ),
    );
    overlay.insert(_hoverEntry!);
  }

  void _removeHoverCard() {
    _hoverEntry?.remove();
    _hoverEntry = null;
  }

  void _handleTap() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final modifierPressed =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);

    _removeHoverCard();
    if (modifierPressed && widget.onSwitchLens != null) {
      widget.onSwitchLens!(widget.entity);
    } else {
      ref.read(peekProvider.notifier).open(widget.entity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entity = widget.entity;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _scheduleHoverCard(),
        onExit: (_) => _cancelHoverCard(),
        child: GestureDetector(
          onTap: _handleTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(SolRadius.xs),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(entity.domain.icon, size: 14, color: scheme.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    entity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: entity.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntityHoverCard extends StatelessWidget {
  final WorkspaceEntityRef entity;
  final VoidCallback onOpenPeek;
  final VoidCallback? onQuickAction;

  const _EntityHoverCard({
    required this.entity,
    required this.onOpenPeek,
    this.onQuickAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SolSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(entity.domain.icon, size: 16, color: scheme.primary),
                const SizedBox(width: SolSpace.xs),
                Text(
                  entity.domain.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (entity.status != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(SolRadius.xs),
                    ),
                    child: Text(
                      entity.status!,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: SolSpace.xs),
            Text(
              entity.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (entity.subtitle != null && entity.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                entity.subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: SolSpace.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onQuickAction != null) ...[
                  TextButton.icon(
                    onPressed: onQuickAction,
                    icon: Icon(
                      entity.isCompleted
                          ? Symbols.check_box_rounded
                          : Symbols.check_box_outline_blank_rounded,
                      size: 16,
                    ),
                    label: Text(entity.isCompleted ? 'Reopen' : 'Complete'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: SolSpace.xs),
                ],
                FilledButton.tonal(
                  onPressed: onOpenPeek,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Open in Peek'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
