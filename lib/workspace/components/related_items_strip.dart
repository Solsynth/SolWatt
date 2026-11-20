import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/entity_pill.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Collapsible cross-domain backlinks strip rendered at the footer/inspector
/// of every detail view (Email thread, Page, Task, File preview).
class RelatedItemsStrip extends ConsumerStatefulWidget {
  final WorkspaceEntityRef entity;
  final List<WorkspaceEntityRef> extraItems;
  final ValueChanged<WorkspaceEntityRef>? onSwitchLens;

  const RelatedItemsStrip({
    super.key,
    required this.entity,
    this.extraItems = const [],
    this.onSwitchLens,
  });

  @override
  ConsumerState<RelatedItemsStrip> createState() => _RelatedItemsStripState();
}

class _RelatedItemsStripState extends ConsumerState<RelatedItemsStrip> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final links = ref.watch(backlinksProvider);
    final linked = ref
        .read(backlinksProvider.notifier)
        .relatedFor(widget.entity);
    if (links.isEmpty && linked.isEmpty && widget.extraItems.isEmpty) {
      // Keep watching `links` so updates rebuild the strip.
    }

    final seen = <String>{};
    final items = <WorkspaceEntityRef>[];
    for (final item in [...linked, ...widget.extraItems]) {
      if (item.key != widget.entity.key && seen.add(item.key)) {
        items.add(item);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SolRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(SolRadius.sm),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SolSpace.md,
                vertical: SolSpace.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.link_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: SolSpace.sm),
                  Text(
                    // A count belongs in the label's own badge, not in
                    // parentheses the reader has to parse.
                    'relatedItems'.tr(namedArgs: {'count': '${items.length}'}),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Symbols.keyboard_arrow_up_rounded
                        : Symbols.keyboard_arrow_down_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SolSpace.md,
                0,
                SolSpace.md,
                SolSpace.md,
              ),
              child: items.isEmpty
                  ? Text(
                      'noLinkedItems'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : Wrap(
                      spacing: SolSpace.sm,
                      runSpacing: SolSpace.sm,
                      children: [
                        for (final item in items)
                          EntityPill(
                            entity: item,
                            onSwitchLens: widget.onSwitchLens,
                          ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
