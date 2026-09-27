import 'package:flutter/material.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/theme.dart';

/// Prompts for a single name (or similar string) in a [SheetScaffold] sheet.
Future<String?> showNameInputSheet(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String? initialValue,
  String? subtitle,
  IconData icon = Symbols.title,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _NameInputSheet(
      title: title,
      label: label,
      confirmLabel: confirmLabel,
      initialValue: initialValue,
      subtitle: subtitle,
      icon: icon,
    ),
  );
}

class _NameInputSheet extends StatefulWidget {
  const _NameInputSheet({
    required this.title,
    required this.label,
    required this.confirmLabel,
    this.initialValue,
    this.subtitle,
    required this.icon,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String? initialValue;
  final String? subtitle;
  final IconData icon;

  @override
  State<_NameInputSheet> createState() => _NameInputSheetState();
}

class _NameInputSheetState extends State<_NameInputSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SheetScaffold(
      titleText: widget.title,
      heightFactor: 0.4,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.subtitle != null) ...[
              Text(
                widget.subtitle!,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.label,
                prefixIcon: inputPrefixIcon(widget.icon),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
          ],
        ),
      ),
    );
  }
}
