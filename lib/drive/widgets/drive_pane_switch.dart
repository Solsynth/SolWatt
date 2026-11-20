import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/drive/widgets/file_list_view.dart' show FileListMode;

/// The Drive lens has two panes, not two lenses: cloud folders and service
/// attachments. Choosing one retargets the open drive browser. The desktop
/// sidebar and the phone switcher sheet both carry it.
class DrivePaneSwitch extends StatelessWidget {
  final FileListMode mode;
  final ValueChanged<FileListMode> onSelect;

  const DrivePaneSwitch({
    super.key,
    required this.mode,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SegmentedButton<FileListMode>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: Theme.of(context).textTheme.labelSmall,
        selectedForegroundColor: scheme.onSecondaryContainer,
        selectedBackgroundColor: scheme.secondaryContainer,
      ),
      segments: const [
        ButtonSegment(
          value: FileListMode.normal,
          label: Text('Cloud'),
          icon: Icon(Symbols.folder_rounded, size: 15),
        ),
        ButtonSegment(
          value: FileListMode.unindexed,
          label: Text('Assets'),
          icon: Icon(Symbols.inventory_2_rounded, size: 15),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selection) => onSelect(selection.first),
    );
  }
}
