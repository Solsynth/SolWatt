import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/drive/usage.dart';
import 'package:solwatt/drive/widgets/usage_overview.dart';
import 'package:solwatt/shared/widgets/layouts/sheet_scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart'
    show formatFileSize;

/// Quiet storage readout: the meter is the headline, the numbers carry the
/// exact figures. Tapping it is the drive's own usage sheet, so the surface
/// holding it never becomes a dashboard.
class DriveStorageMeter extends StatelessWidget {
  final DriveStorageSnapshot storage;

  const DriveStorageMeter({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = storage.ratio;
    final tone = ratio >= 0.9
        ? scheme.error
        : ratio >= 0.75
        ? scheme.tertiary
        : scheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Symbols.cloud_rounded,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Storage',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${(ratio * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            color: tone,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${formatFileSize(storage.usedBytes)} of ${formatFileSize(storage.totalBytes)}',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The drive's usage sheet. One entry point so the sidebar dock and the phone
/// switcher open the same readout.
void showDriveUsageSheet(BuildContext context, DriveStorageSnapshot storage) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => SheetScaffold(
      titleText: 'usageOverview'.tr(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: UsageOverviewWidget(usage: storage.usage, quota: storage.quota),
      ),
    ),
  );
}
