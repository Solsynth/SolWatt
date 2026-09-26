import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart'
    as foundation;
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/page_scaffold.dart';

/// Matches the generated [GateRoute] name for navigation outside typed routes.
const _gateRouteName = 'GateRoute';

class WorkspaceDraft {
  const WorkspaceDraft({
    required this.slug,
    required this.name,
    this.description,
    this.type = WorkspaceType.organization,
    this.pictureId,
    this.updatePicture = false,
    this.backgroundId,
    this.updateBackground = false,
  });
  final String slug;
  final String name;
  final String? description;
  final int type;
  final String? pictureId;
  final bool updatePicture;
  final String? backgroundId;
  final bool updateBackground;
}

Future<void> createWorkspaceAction(BuildContext context, WidgetRef ref) async {
  final profile = await ref.read(userInfoProvider.future);
  if (!context.mounted) return;
  final draft = await showWorkspaceEditor(context, profile: profile);
  if (draft == null) return;
  try {
    final workspace = await ref
        .read(wattEngineClientProvider)
        .createWorkspace(
          slug: draft.slug,
          name: draft.name,
          description: draft.description,
          type: draft.type,
          pictureId: draft.updatePicture ? draft.pictureId : null,
          backgroundId: draft.updateBackground ? draft.backgroundId : null,
        );
    ref.invalidate(workspacesProvider);
    await selectWorkspace(ref.read(secureStorageProvider), workspace);
    invalidateWorkspaceScope(ref);
    showSnackBar('workspaceCreated'.tr());
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> editWorkspaceAction(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
  final draft = await showWorkspaceEditor(context, workspace: workspace);
  if (draft == null) return;
  try {
    await ref
        .read(wattEngineClientProvider)
        .updateWorkspace(
          slug: workspace.slug,
          name: draft.name,
          description: draft.description,
          pictureId: draft.pictureId,
          updatePicture: draft.updatePicture,
          backgroundId: draft.backgroundId,
          updateBackground: draft.updateBackground,
        );
    ref.invalidate(workspacesProvider);
    invalidateWorkspaceScope(ref);
    showSnackBar('workspaceUpdated'.tr());
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> deleteWorkspaceAction(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
  final confirmed = await showConfirmAlert(
    'deleteWorkspaceConfirm'.tr(),
    'deleteWorkspaceTitle'.tr(namedArgs: {'name': workspace.name}),
    icon: Symbols.delete,
    isDanger: true,
    confirmLabel: 'delete'.tr(),
  );
  if (!confirmed) return;
  try {
    final selected = await ref.read(selectedWorkspaceProvider.future);
    await ref.read(wattEngineClientProvider).deleteWorkspace(workspace.slug);
    if (selected?.id == workspace.id) {
      await clearSelectedWorkspace(ref.read(secureStorageProvider));
    }
    ref.invalidate(workspacesProvider);
    invalidateWorkspaceScope(ref);
    showSnackBar('workspaceDeleted'.tr());
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> activateWorkspaceAction(WidgetRef ref, Workspace workspace) async {
  await selectWorkspace(ref.read(secureStorageProvider), workspace);
  invalidateWorkspaceScope(ref);
  showSnackBar('workspaceNowActive'.tr(namedArgs: {'name': workspace.name}));
}

/// Clears the active workspace selection and returns to the gate's workspace
/// chooser. Exposed from the workspace row's actions menu.
Future<void> leaveWorkspaceAction(BuildContext context, WidgetRef ref) async {
  await clearSelectedWorkspace(ref.read(secureStorageProvider));
  invalidateWorkspaceScope(ref);
  if (!context.mounted) return;
  context.router.replaceAll([const PageRouteInfo(_gateRouteName)]);
}

Future<void> showWorkspaceQuota(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _WorkspacePlanQuotaSheet(workspace: workspace),
);

class _WorkspacePlanQuotaSheet extends ConsumerStatefulWidget {
  const _WorkspacePlanQuotaSheet({required this.workspace});

  final Workspace workspace;

  @override
  ConsumerState<_WorkspacePlanQuotaSheet> createState() =>
      _WorkspacePlanQuotaSheetState();
}

class _WorkspacePlanQuotaSheetState
    extends ConsumerState<_WorkspacePlanQuotaSheet> {
  late Future<_PlanQuotaBundle> _bundle;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final client = ref.read(wattEngineClientProvider);
    final slug = widget.workspace.slug;
    _bundle =
        Future.wait<Object>([
          client.getWorkspacePlanStatus(slug),
          client.getWorkspaceQuota(slug),
        ]).then(
          (results) => _PlanQuotaBundle(
            status: results[0] as WorkspacePlanStatus,
            quota: results[1] as WorkspaceQuota,
          ),
        );
  }

  Future<void> _subscribePlan(int plan, WorkspacePlanPrices? prices) async {
    final planName = WorkspacePlanTier.nameOf(plan);
    final priceLabel = prices == null
        ? null
        : plan == WorkspacePlanTier.pro
        ? '${prices.pro} ${prices.currency}/mo'
        : '${prices.enterprise} ${prices.currency}/mo';
    final confirmed = await showConfirmAlert(
      priceLabel == null
          ? 'createPaymentOrderNoPrice'.tr(
              namedArgs: {'plan': planName, 'name': widget.workspace.name},
            )
          : 'createPaymentOrderWithPrice'.tr(
              namedArgs: {
                'plan': planName,
                'price': priceLabel,
                'name': widget.workspace.name,
              },
            ),
      'subscribeToPlan'.tr(namedArgs: {'plan': planName}),
      confirmLabel: 'continueToPayment'.tr(),
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      final order = await ref
          .read(wattEngineClientProvider)
          .subscribeWorkspacePlan(slug: widget.workspace.slug, plan: plan);
      if (!mounted) return;
      setState(() => _busy = false);

      final opened = await _openOrderPayment(order);
      if (!mounted) return;
      await showOverlayDialog<void>(
        builder: (context, close) => _PaymentOrderDialog(
          planName: planName,
          order: order,
          openedInBrowser: opened,
          onOpenPayment: () => _openOrderPayment(order),
          onClose: () => close(null),
        ),
      );
      if (!mounted) return;
      setState(_reload);
      showSnackBar(
        'orderCreatedScanQr'.tr(namedArgs: {'orderId': order.orderId}),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnackBar(wattApiErrorMessage(error));
    }
  }

  Future<bool> _openOrderPayment(WorkspacePlanOrder order) async {
    if (order.orderId.isEmpty) return false;
    final uri = order.paymentUrl;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final account =
        ref.watch(solWattProfileProvider).value?.account ??
        ref.watch(userInfoProvider).value;
    final isOwner =
        account != null &&
        widget.workspace.ownerAccountId != null &&
        widget.workspace.ownerAccountId == account.id;

    return SheetScaffold(
      titleText: 'planAndQuotas'.tr(),
      heightFactor: 0.78,
      child: FutureBuilder<_PlanQuotaBundle>(
        future: _bundle,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Symbols.error,
              title: 'couldNotLoadPlan'.tr(),
              message: wattApiErrorMessage(snapshot.error!),
              action: FilledButton(
                onPressed: () => setState(_reload),
                child: Text('tryAgain'.tr()),
              ),
            );
          }
          final status = snapshot.data!.status;
          final quota = snapshot.data!.quota;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(
                widget.workspace.name,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusChip(
                    label: status.planName,
                    icon: Symbols.workspace_premium,
                    tone: status.plan == WorkspacePlanTier.free
                        ? StatusChipTone.neutral
                        : StatusChipTone.secondary,
                  ),
                  if (status.isBundled)
                    StatusChip(
                      label: 'yourBundledPro'.tr(),
                      icon: Symbols.card_giftcard,
                      tone: StatusChipTone.primary,
                    ),
                  if (status.planExpiresAt != null)
                    StatusChip(
                      label: 'expires'.tr(
                        namedArgs: {'date': _formatDate(status.planExpiresAt!)},
                      ),
                      icon: Symbols.event,
                      tone: StatusChipTone.neutral,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: Icon(
                    widget.workspace.isIndividual
                        ? Symbols.workspace_premium
                        : Symbols.person,
                    color: scheme.primary,
                  ),
                  title: Text('bundledPro'.tr()),
                  subtitle: Text(
                    widget.workspace.isIndividual
                        ? (status.isBundled
                              ? 'bundledProActivePersonal'.tr()
                              : 'bundledProPersonalEligibility'.tr())
                        : 'bundledProPersonalOnly'.tr(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('paidSubscription'.tr(), style: text.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (status.prices != null) ...[
                        Text(
                          'Pro ${status.prices!.pro} ${status.prices!.currency}/mo · '
                          'Enterprise ${status.prices!.enterprise} '
                          '${status.prices!.currency}/mo',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!isOwner)
                        Text(
                          'onlyOwnerCanPurchase'.tr(),
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else if (status.plan == WorkspacePlanTier.enterprise &&
                          !status.isBundled)
                        Text(
                          'alreadyOnEnterprise'.tr(),
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else ...[
                        if (status.plan < WorkspacePlanTier.pro ||
                            status.isBundled)
                          FilledButton.tonalIcon(
                            onPressed: _busy
                                ? null
                                : () => _subscribePlan(
                                    WorkspacePlanTier.pro,
                                    status.prices,
                                  ),
                            icon: const Icon(Symbols.payments, size: 18),
                            label: Text(
                              status.prices == null
                                  ? 'subscribeToPro'.tr()
                                  : 'subscribeToProWithPrice'.tr(
                                      namedArgs: {
                                        'price':
                                            '${status.prices!.pro} ${status.prices!.currency}',
                                      },
                                    ),
                            ),
                          ),
                        if (status.plan < WorkspacePlanTier.enterprise) ...[
                          if (status.plan < WorkspacePlanTier.pro ||
                              status.isBundled)
                            const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _subscribePlan(
                                    WorkspacePlanTier.enterprise,
                                    status.prices,
                                  ),
                            icon: const Icon(Symbols.diamond, size: 18),
                            label: Text(
                              status.prices == null
                                  ? 'subscribeToEnterprise'.tr()
                                  : 'subscribeToEnterpriseWithPrice'.tr(
                                      namedArgs: {
                                        'price':
                                            '${status.prices!.enterprise} ${status.prices!.currency}',
                                      },
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('resourceLimits'.tr(), style: text.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final (i, entry) in quota.limits.entries.indexed) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _quotaLabel(entry.key),
                                style: text.bodyMedium,
                              ),
                            ),
                            Text(
                              _formatQuota(entry.value),
                              style: text.labelLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlanQuotaBundle {
  const _PlanQuotaBundle({required this.status, required this.quota});
  final WorkspacePlanStatus status;
  final WorkspaceQuota quota;
}

class _PaymentOrderDialog extends StatelessWidget {
  const _PaymentOrderDialog({
    required this.planName,
    required this.order,
    required this.openedInBrowser,
    required this.onOpenPayment,
    required this.onClose,
  });

  final String planName;
  final WorkspacePlanOrder order;
  final bool openedInBrowser;
  final Future<bool> Function() onOpenPayment;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final paymentLink = order.paymentUrl.toString();
    final media = MediaQuery.sizeOf(context);
    final shape =
        theme.dialogTheme.shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));

    final maxWidth = (media.width - 48).clamp(280.0, kDialogMaxWidth);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 280,
        maxWidth: maxWidth,
        maxHeight: media.height * 0.85,
      ),
      child: Material(
        color: theme.dialogTheme.backgroundColor ?? scheme.surfaceContainerHigh,
        elevation: theme.dialogTheme.elevation ?? 6,
        shadowColor: theme.shadowColor,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'orderCreatedTitle'.tr(namedArgs: {'plan': planName}),
                style: text.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                openedInBrowser
                    ? 'browserTabMayHaveOpened'.tr()
                    : 'scanQrToPay'.tr(),
                style: text.bodyMedium,
              ),
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: QrImageView(
                        data: paymentLink,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                        eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: scheme.onSurface,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: scheme.onSurface,
                        ),
                        errorStateBuilder: (context, error) => Center(
                          child: Text(
                            'couldNotRenderQr'.tr(),
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(
                paymentLink,
                style: text.bodySmall?.copyWith(color: scheme.primary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'orderAmount'.tr(
                  namedArgs: {
                    'orderId': order.orderId,
                    'amount': '${order.amount} ${order.currency}',
                  },
                ),
                textAlign: TextAlign.center,
                style: text.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'afterPaymentSettles'.tr(),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () async {
                      await onOpenPayment();
                    },
                    child: Text('openInBrowser'.tr()),
                  ),
                  FilledButton(onPressed: onClose, child: Text('done'.tr())),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _quotaLabel(String key) => switch (key) {
  'max_projects' => 'projects'.tr(),
  'max_members' => 'members'.tr(),
  'max_tasks_per_project' => 'tasksPerProject'.tr(),
  'max_broads_per_project' => 'boardsPerProject'.tr(),
  'max_storage_bytes' => 'storage'.tr(),
  _ => key.replaceAll('_', ' '),
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

Future<void> showWorkspaceMembers(BuildContext context, Workspace workspace) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WorkspaceMembersSheet(workspace: workspace),
    );

class _WorkspaceMembersSheet extends ConsumerStatefulWidget {
  const _WorkspaceMembersSheet({required this.workspace});

  final Workspace workspace;

  @override
  ConsumerState<_WorkspaceMembersSheet> createState() =>
      _WorkspaceMembersSheetState();
}

class _WorkspaceMembersSheetState
    extends ConsumerState<_WorkspaceMembersSheet> {
  late Future<List<WorkspaceMember>> _members;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _members = ref
      .read(wattEngineClientProvider)
      .listWorkspaceMembers(widget.workspace.slug);

  Future<void> _invite() async {
    final account = await showModalBottomSheet<SnAccount>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _AccountPickerSheet(client: ref.read(wattEngineClientProvider)),
    );
    if (account == null || !mounted) return;
    final role = await _selectRole(context, title: 'inviteMember'.tr());
    if (role == null || !mounted) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .inviteWorkspaceMember(
            slug: widget.workspace.slug,
            accountId: account.id,
            role: role,
          );
      _refresh('invitationSent'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _changeRole(WorkspaceMember member) async {
    final role = await _selectRole(
      context,
      title: 'changeRole'.tr(),
      selectedRole: member.role,
    );
    if (role == null || role == member.role || !mounted) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .updateWorkspaceMemberRole(
            slug: widget.workspace.slug,
            accountId: member.accountId,
            role: role,
          );
      _refresh('memberRoleUpdated'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _remove(WorkspaceMember member) async {
    final confirmed = await showConfirmAlert(
      'removeMemberConfirm'.tr(),
      'removeMember'.tr(),
      icon: Symbols.person_remove,
      isDanger: true,
      confirmLabel: 'removeMember'.tr(),
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .removeWorkspaceMember(
            slug: widget.workspace.slug,
            accountId: member.accountId,
          );
      _refresh('memberRemoved'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  void _refresh(String message) {
    setState(_reload);
    showSnackBar(message);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SheetScaffold(
      titleText: 'membersTitle'.tr(),
      heightFactor: 0.78,
      actions: [
        FilledButton.tonalIcon(
          onPressed: _invite,
          icon: const Icon(Symbols.person_add, size: 18),
          label: Text('invite'.tr()),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.workspace.name,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<WorkspaceMember>>(
                future: _members,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return EmptyState(
                      icon: Symbols.error,
                      title: 'couldNotLoadMembers'.tr(),
                      message: snapshot.error.toString(),
                      action: FilledButton(
                        onPressed: () => setState(_reload),
                        child: Text('tryAgain'.tr()),
                      ),
                    );
                  }
                  final members = snapshot.data ?? const [];
                  if (members.isEmpty) {
                    return EmptyState(
                      icon: Symbols.group,
                      title: 'noMembers'.tr(),
                      message: 'inviteToCollaborate'.tr(),
                    );
                  }
                  return ListView.separated(
                    itemCount: members.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final member = members[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _AccountAvatar(
                          picture: member.picture,
                          label: member.label,
                          size: 44,
                        ),
                        title: Text(member.label),
                        subtitle: Text(
                          '${_roleName(member.role)} · ${member.subtitleHandle}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'role') _changeRole(member);
                            if (action == 'remove') _remove(member);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'role',
                              child: Text(
                                '${'role'.tr()}: ${_roleName(member.role)}',
                              ),
                            ),
                            if (member.role != 100)
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('removeMember'.tr()),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<int?> _selectRole(
  BuildContext context, {
  required String title,
  int? selectedRole,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SheetScaffold(
    titleText: title,
    heightFactor: 0.45,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      children: [
        for (final role in const [25, 50, 75, 100])
          ListTile(
            title: Text(_roleName(role)),
            trailing: selectedRole == role ? const Icon(Symbols.check) : null,
            onTap: () => Navigator.pop(context, role),
          ),
      ],
    ),
  ),
);

String _roleName(int role) => switch (role) {
  25 => 'viewer'.tr(),
  50 => 'memberRole'.tr(),
  75 => 'admin'.tr(),
  100 => 'owner'.tr(),
  _ => 'role'.tr(args: [role.toString()]),
};

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.picture,
    required this.label,
    this.size = 40,
  });

  final SnCloudFileReference? picture;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = picture == null ? null : cloudFileDisplayUrl(picture!);
    final initial = label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();

    if (url != null) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialCircle(scheme, initial),
        ),
      );
    }
    return _initialCircle(scheme, initial);
  }

  Widget _initialCircle(ColorScheme scheme, String initial) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _AccountPickerSheet extends StatefulWidget {
  const _AccountPickerSheet({required this.client});

  final WattEngineClient client;

  @override
  State<_AccountPickerSheet> createState() => _AccountPickerSheetState();
}

class _AccountPickerSheetState extends State<_AccountPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<List<SnAccount>>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _results = widget.client.searchAccounts(query);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      titleText: 'inviteMember'.tr(),
      heightFactor: 0.7,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          children: [
            SearchBar(
              controller: _controller,
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 24),
              ),
              hintText: 'searchAccounts'.tr(),
              leading: const Icon(Symbols.search),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _results == null
                  ? Center(child: Text('searchAccountToInvite'.tr()))
                  : FutureBuilder<List<SnAccount>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text(snapshot.error.toString()));
                        }
                        final accounts = snapshot.data ?? const [];
                        if (accounts.isEmpty) {
                          return Center(child: Text('noAccountsFound'.tr()));
                        }
                        return ListView.builder(
                          itemCount: accounts.length,
                          itemBuilder: (context, index) {
                            final account = accounts[index];
                            return ListTile(
                              leading: _AccountAvatar(
                                picture: account.profilePicture,
                                label: account.solWattDisplayName,
                                size: 40,
                              ),
                              title: Text(account.solWattDisplayName),
                              subtitle: Text('@${account.name}'),
                              onTap: () => Navigator.pop(context, account),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatQuota(dynamic value) {
  if (value is num && value >= 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
  }
  return value.toString();
}

Future<WorkspaceDraft?> showWorkspaceEditor(
  BuildContext context, {
  Workspace? workspace,
  SnAccount? profile,
}) {
  return showModalBottomSheet<WorkspaceDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _WorkspaceEditorSheet(workspace: workspace, profile: profile),
  );
}

class _WorkspaceEditorSheet extends ConsumerStatefulWidget {
  const _WorkspaceEditorSheet({this.workspace, this.profile});

  final Workspace? workspace;
  final SnAccount? profile;

  @override
  ConsumerState<_WorkspaceEditorSheet> createState() =>
      _WorkspaceEditorSheetState();
}

class _WorkspaceEditorSheetState extends ConsumerState<_WorkspaceEditorSheet> {
  late final TextEditingController _slug;
  late final TextEditingController _name;
  late final TextEditingController _description;
  SnCloudFileReference? _picture;
  SnCloudFileReference? _background;
  var _pictureChanged = false;
  var _backgroundChanged = false;

  @override
  void initState() {
    super.initState();
    final workspace = widget.workspace;
    _slug = TextEditingController(text: workspace?.slug ?? '');
    _name = TextEditingController(text: workspace?.name ?? '');
    _description = TextEditingController(text: workspace?.description ?? '');
    _picture = workspace?.picture;
    _background = workspace?.background;
  }

  @override
  void dispose() {
    _slug.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    final workspaceId = widget.workspace?.id;
    final file = await pickCloudImageReference(
      context,
      ref,
      usage: 'workspace.picture',
      workspaceId: workspaceId,
      title: 'workspaceIcon'.tr(),
    );
    if (file == null || !mounted) return;
    setState(() {
      _picture = file;
      _pictureChanged = true;
    });
  }

  Future<void> _pickBackground() async {
    final workspaceId = widget.workspace?.id;
    final file = await pickCloudImageReference(
      context,
      ref,
      usage: 'workspace.background',
      workspaceId: workspaceId,
      title: 'backgroundImage'.tr(),
    );
    if (file == null || !mounted) return;
    setState(() {
      _background = file;
      _backgroundChanged = true;
    });
  }

  void _submit() {
    final slugText = _slug.text.trim();
    final nameText = _name.text.trim();
    if (widget.workspace == null && slugText.isEmpty) {
      showSnackBar('slugIsRequired'.tr());
      return;
    }
    if (nameText.isEmpty) {
      showSnackBar('nameIsRequired'.tr());
      return;
    }
    Navigator.pop(
      context,
      WorkspaceDraft(
        slug: slugText,
        name: nameText,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        type: WorkspaceType.organization,
        pictureId: _picture?.id,
        updatePicture: _pictureChanged,
        backgroundId: _background?.id,
        updateBackground: _backgroundChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SheetScaffold(
      titleText: workspace == null ? 'newWorkspace'.tr() : 'editWorkspace'.tr(),
      heightFactor: 0.82,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: _pickPicture,
                  borderRadius: BorderRadius.circular(16),
                  child: CloudFileAvatar(
                    file: _picture,
                    fallbackIcon: Symbols.workspaces,
                    size: 72,
                    assumeImage: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('workspaceIcon'.tr(), style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'workspaceIconDescription'.tr(),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _pickPicture,
                            icon: const Icon(Symbols.upload, size: 18),
                            label: Text(
                              _picture == null ? 'upload'.tr() : 'change'.tr(),
                            ),
                          ),
                          if (_picture != null)
                            TextButton(
                              onPressed: () => setState(() {
                                _picture = null;
                                _pictureChanged = true;
                              }),
                              child: Text('clear'.tr()),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CloudFileAvatar(
                file: _background,
                fallbackIcon: Symbols.wallpaper,
                size: 40,
              ),
              title: Text('backgroundImage'.tr()),
              subtitle: Text(
                _background == null ? 'optional'.tr() : _background!.name,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_background != null)
                    IconButton(
                      tooltip: 'clearBackground'.tr(),
                      icon: const Icon(Symbols.close),
                      onPressed: () => setState(() {
                        _background = null;
                        _backgroundChanged = true;
                      }),
                    ),
                  IconButton(
                    tooltip: 'chooseBackground'.tr(),
                    icon: const Icon(Symbols.upload),
                    onPressed: _pickBackground,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (workspace == null) ...[
              TextField(
                controller: _slug,
                decoration: InputDecoration(
                  labelText: 'slug'.tr(),
                  hintText: 'slugHint'.tr(),
                  prefixIcon: inputPrefixIcon(Symbols.link),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Symbols.business),
                  title: Text('organizationWorkspace'.tr()),
                  subtitle: Text('organizationWorkspaceDescription'.tr()),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'name'.tr(),
                prefixIcon: inputPrefixIcon(Symbols.badge),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: 'description'.tr(),
                alignLabelWithHint: true,
                prefixIcon: inputPrefixIcon(Symbols.notes, maxLines: 4),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submit,
              child: Text(
                workspace == null ? 'createWorkspace'.tr() : 'saveChanges'.tr(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkspaceList extends ConsumerWidget {
  const WorkspaceList({
    super.key,
    required this.onActivate,
    this.manageActions = false,
    this.emptyMessage,
    this.scrollable = true,
  });

  final Future<void> Function(Workspace workspace) onActivate;
  final bool manageActions;
  final String? emptyMessage;
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(workspacesProvider);
    final selected = ref.watch(selectedWorkspaceProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return workspaces.when(
      loading: () => const PageLoading(),
      error: (error, _) => PageError(
        message: error.toString(),
        onRetry: () => ref.invalidate(workspacesProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Symbols.workspaces,
            title: 'noWorkspaces'.tr(),
            message: emptyMessage ?? 'noWorkspacesEmpty'.tr(),
            action: FilledButton.icon(
              onPressed: () => createWorkspaceAction(context, ref),
              icon: const Icon(Symbols.add),
              label: Text('createWorkspace'.tr()),
            ),
          );
        }

        Widget itemBuilder(BuildContext context, int index) {
          final workspace = items[index];
          final isActive = selected?.id == workspace.id;
          final planLabel = workspace.isIndividual
              ? '${'personalWorkspace'.tr()} · ${workspace.planName}'
              : '${'organization'.tr()} · ${workspace.planName}';
          final background = workspace.background;
          final backgroundPreview = background == null
              ? null
              : foundation.cloudFileImageProvider(
                  serverUrl: kSolarNetworkApiBase,
                  id: background.id,
                  storageUrl: background.storageUrl,
                  workspaceId: workspace.id,
                );

          return Card(
            clipBehavior: Clip.antiAlias,
            color: isActive
                ? scheme.primaryContainer.withValues(alpha: 0.55)
                : scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isActive
                  ? BorderSide(color: scheme.primary.withValues(alpha: 0.45))
                  : BorderSide.none,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onActivate(workspace),
              child: SizedBox(
                height: 60,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (backgroundPreview != null)
                      Image(
                        image: backgroundPreview,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    if (backgroundPreview != null)
                      ColoredBox(color: scheme.surface.withValues(alpha: 0.82)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(1.5),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CloudFileAvatar(
                                  file: workspace.picture,
                                  workspaceId: workspace.id,
                                  fallbackIcon: Symbols.workspaces,
                                  size: 40,
                                  selected: isActive,
                                  borderRadius: workspace.isIndividual
                                      ? BorderRadius.circular(999)
                                      : null,
                                  assumeImage: true,
                                ),
                                if (isActive)
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: scheme.surface,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Symbols.check_circle,
                                        size: 16,
                                        color: scheme.primary,
                                        fill: 1,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  workspace.name,
                                  style: text.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  planLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (manageActions)
                            PopupMenuButton<String>(
                              tooltip: 'workspaceActions'.tr(),
                              icon: Icon(
                                Symbols.more_vert,
                                color: scheme.onSurfaceVariant,
                              ),
                              onSelected: (value) {
                                switch (value) {
                                  case 'quota':
                                    showWorkspaceQuota(context, ref, workspace);
                                  case 'members':
                                    showWorkspaceMembers(context, workspace);
                                  case 'edit':
                                    editWorkspaceAction(
                                      context,
                                      ref,
                                      workspace,
                                    );
                                  case 'leave':
                                    leaveWorkspaceAction(context, ref);
                                  case 'delete':
                                    deleteWorkspaceAction(
                                      context,
                                      ref,
                                      workspace,
                                    );
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'quota',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Symbols.workspace_premium,
                                    ),
                                    title: Text('planAndQuotas'.tr()),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'members',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Symbols.group),
                                    title: Text('manageMembers'.tr()),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Symbols.edit),
                                    title: Text('edit'.tr()),
                                  ),
                                ),
                                if (isActive)
                                  PopupMenuItem(
                                    value: 'leave',
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Symbols.logout),
                                      title: Text('leaveWorkspace'.tr()),
                                    ),
                                  ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Symbols.delete,
                                      color: scheme.error,
                                    ),
                                    title: Text(
                                      'delete'.tr(),
                                      style: TextStyle(color: scheme.error),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Icon(
                              Symbols.chevron_right,
                              color: scheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (!scrollable) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  itemBuilder(context, index),
                  if (index < items.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}
