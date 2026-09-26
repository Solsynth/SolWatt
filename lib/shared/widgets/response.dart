import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Centered error pane shown by [PaginationList]/[PaginationWidget] when the
/// pagination provider fails. Renders an EmptyState-style block with the
/// resolved error text and an optional retry button.
class ResponseErrorWidget extends StatelessWidget {
  final dynamic error;
  final String? message;
  final VoidCallback? onRetry;

  const ResponseErrorWidget({
    super.key,
    this.error,
    this.message,
    this.onRetry,
  });

  String get _resolvedMessage {
    if (message case final String m when m.isNotEmpty) return m;
    if (error is DioException) {
      final data = (error as DioException).response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      final detail = (error as DioException).message;
      if (detail != null && detail.isNotEmpty) return detail;
    }
    return error?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final resolvedMessage = _resolvedMessage;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.error_outline,
                  size: 32,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              if (resolvedMessage.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  resolvedMessage,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text('retry').tr(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
