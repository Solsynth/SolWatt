import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/workspace_header.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_search.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Opens the Federated Omnibox modal (Cmd/Ctrl + K or Mobile Search Pill).
Future<void> showFederatedOmnibox(
  BuildContext context, {
  ValueChanged<WorkspaceEntityRef>? onSwitchLens,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _FederatedOmniboxDialog(onSwitchLens: onSwitchLens),
  );
}

class _FederatedOmniboxDialog extends ConsumerStatefulWidget {
  final ValueChanged<WorkspaceEntityRef>? onSwitchLens;

  const _FederatedOmniboxDialog({this.onSwitchLens});

  @override
  ConsumerState<_FederatedOmniboxDialog> createState() =>
      _FederatedOmniboxDialogState();
}

class _FederatedOmniboxDialogState
    extends ConsumerState<_FederatedOmniboxDialog> {
  final TextEditingController _controller = TextEditingController();
  WorkspaceDomain? _filter;
  final Set<WorkspaceDomain> _collapsedDomains = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openItem(WorkspaceEntityRef entity, {bool fullView = false}) {
    Navigator.of(context).pop();
    ref.read(recentEntitiesProvider.notifier).record(entity);
    if (fullView && widget.onSwitchLens != null) {
      widget.onSwitchLens!(entity);
    } else {
      ref.read(peekProvider.notifier).open(entity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rawQuery = _controller.text.trim();
    var effectiveFilter = _filter;
    var cleanQuery = rawQuery;

    for (final domain in WorkspaceDomain.values) {
      if (cleanQuery.toLowerCase().contains(domain.filterChipLabel)) {
        effectiveFilter ??= domain;
        cleanQuery = cleanQuery
            .replaceAll(
              RegExp(domain.filterChipLabel, caseSensitive: false),
              '',
            )
            .trim();
      }
    }

    final results = searchWorkspaceEntities(
      ref,
      cleanQuery,
      domainFilter: effectiveFilter,
      limitPerDomain: 6,
    );

    final topHits = results.take(4).toList();
    final grouped = <WorkspaceDomain, List<WorkspaceEntityRef>>{};
    for (final item in results) {
      grouped.putIfAbsent(item.domain, () => []).add(item);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(
          horizontal: SolSpace.lg,
          vertical: SolSpace.xxxl,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SolRadius.md),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SolSpace.md,
                  SolSpace.md,
                  SolSpace.md,
                  SolSpace.sm,
                ),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: scheme.surfaceContainerHigh,
                    prefixIcon: const Icon(Symbols.search_rounded),
                    hintText: 'searchHint'.tr(),
                    suffixIcon: IconButton(
                      icon: const Icon(Symbols.close_rounded, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SolRadius.sm),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: SolSpace.md),
                child: Row(
                  children: [
                    FilterChip(
                      label: Text('all'.tr()),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                    ),
                    const SizedBox(width: SolSpace.xs),
                    for (final domain in WorkspaceDomain.values) ...[
                      FilterChip(
                        avatar: Icon(domain.icon, size: 15),
                        label: Text(domain.filterChipLabel),
                        selected: _filter == domain,
                        onSelected: (selected) =>
                            setState(() => _filter = selected ? domain : null),
                      ),
                      const SizedBox(width: SolSpace.xs),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: SolSpace.sm),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          'searchNoResults'.tr(),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(SolSpace.sm),
                        children: [
                          if (effectiveFilter == null &&
                              topHits.isNotEmpty) ...[
                            _GroupTitle(
                              title: 'topHits'.tr(),
                              count: topHits.length,
                            ),
                            for (final item in topHits)
                              WorkspaceListRow(
                                compact: true,
                                leading: Icon(
                                  item.domain.icon,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                title: Text(item.title),
                                subtitle: Text(
                                  '${item.domain.label}${item.subtitle != null ? ' · ${item.subtitle}' : ''}',
                                ),
                                trailing: IconButton(
                                  tooltip: 'openInFullView'.tr(),
                                  icon: const Icon(
                                    Symbols.open_in_new_rounded,
                                    size: 16,
                                  ),
                                  onPressed: () =>
                                      _openItem(item, fullView: true),
                                ),
                                onTap: () => _openItem(item),
                              ),
                            const SizedBox(height: SolSpace.sm),
                          ],
                          for (final entry in grouped.entries) ...[
                            InkWell(
                              borderRadius: BorderRadius.circular(SolRadius.xs),
                              onTap: () => setState(() {
                                if (_collapsedDomains.contains(entry.key)) {
                                  _collapsedDomains.remove(entry.key);
                                } else {
                                  _collapsedDomains.add(entry.key);
                                }
                              }),
                              child: _GroupTitle(
                                title: entry.key.label,
                                count: entry.value.length,
                                collapsed: _collapsedDomains.contains(
                                  entry.key,
                                ),
                              ),
                            ),
                            if (!_collapsedDomains.contains(entry.key))
                              for (final item in entry.value)
                                WorkspaceListRow(
                                  compact: true,
                                  leading: Icon(
                                    item.domain.icon,
                                    size: 18,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  title: Text(item.title),
                                  subtitle: item.subtitle != null
                                      ? Text(item.subtitle!)
                                      : null,
                                  trailing: IconButton(
                                    tooltip: 'openInFullView'.tr(),
                                    icon: const Icon(
                                      Symbols.open_in_new_rounded,
                                      size: 16,
                                    ),
                                    onPressed: () =>
                                        _openItem(item, fullView: true),
                                  ),
                                  onTap: () => _openItem(item),
                                ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  final String title;
  final int count;
  final bool? collapsed;

  const _GroupTitle({required this.title, required this.count, this.collapsed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SolSpace.sm,
        vertical: SolSpace.xs,
      ),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: SolSpace.xs),
          Text(
            '($count)',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          if (collapsed != null)
            Icon(
              collapsed!
                  ? Symbols.keyboard_arrow_down_rounded
                  : Symbols.keyboard_arrow_up_rounded,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}
