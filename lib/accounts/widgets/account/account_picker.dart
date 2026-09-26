import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:solwatt/core/network.dart';
import 'package:solwatt/shared/widgets/layouts/sheet_scaffold.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

/// Default search implementation: queries the Solar Network account search
/// endpoint with the authenticated client's Dio (same endpoint Solian used).
Future<List<SnAccount>> _searchAccounts(WidgetRef ref, String query) async {
  if (query.trim().isEmpty) return const [];
  final client = ref.read(solarNetworkClientProvider);
  final response = await client.dio.get<List<dynamic>>(
    '/stargate/accounts/search',
    queryParameters: {'query': query.trim()},
  );
  return (response.data ?? const [])
      .whereType<Map>()
      .map((json) => SnAccount.fromJson(Map<String, dynamic>.from(json)))
      .toList();
}

/// Bottom-sheet picker for a single Solar Network account.
///
/// Thin replacement for Solian's picker (which pulled in account_pod,
/// route.gr and badge infrastructure). The sheet lists accounts by name and
/// pops with the selected [SnAccount] (or `null` when dismissed).
///
/// The caller wraps it in `showModalBottomSheet<SnAccount>`; the optional
/// [search] callback overrides the default solar-network search.
class AccountPickerSheet extends HookConsumerWidget {
  final String? title;
  final Future<List<SnAccount>> Function(String query)? search;

  const AccountPickerSheet({super.key, this.title, this.search});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final debouncedQuery = useState<String>('');
    final debounceTimer = useRef<Timer?>(null);
    const debounceDuration = Duration(milliseconds: 300);

    void onSearchChanged(String query) {
      debounceTimer.value?.cancel();
      debounceTimer.value = Timer(debounceDuration, () {
        debouncedQuery.value = query;
      });
    }

    Future<List<SnAccount>> runSearch(String query) {
      final custom = search;
      if (custom != null) return custom(query);
      return _searchAccounts(ref, query);
    }

    final accountsFuture = useMemoized(
      () => runSearch(debouncedQuery.value),
      [debouncedQuery.value, search],
    );

    return SheetScaffold(
      showHeader: false,
      heightFactor: 0.6,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: MediaQuery.of(context).padding.top + 16,
          bottom: 8,
        ),
        child: Column(
          children: [
            Row(
              children: [
                if (title != null) ...[
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else
                  Expanded(
                    child: SearchBar(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      hintText: 'searchAccounts'.tr(),
                      elevation: const WidgetStatePropertyAll(2),
                      leading: Icon(
                        Symbols.search,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Symbols.close,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<SnAccount>>(
                future: accountsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      debouncedQuery.value.isNotEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final accounts = snapshot.data ?? const <SnAccount>[];
                  if (accounts.isEmpty && debouncedQuery.value.isEmpty) {
                    return Center(
                      child: Text(
                        'searchAccountsHint'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  if (accounts.isEmpty) {
                    return Center(
                      child: Text('noResults'.tr()),
                    );
                  }
                  return ListView.builder(
                    itemCount: accounts.length,
                    itemBuilder: (context, index) {
                      final account = accounts[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            account.nick.isEmpty
                                ? '?'
                                : account.nick.characters.first,
                          ),
                        ),
                        title: Text(account.nick),
                        subtitle: Text('@${account.name}'),
                        onTap: () => Navigator.of(context).pop(account),
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
