import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/websocket.dart';

const _mailboxWork = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

/// The gateway connection, with the packet stream under the test's control.
class _FakeWebSocket extends WebSocketService {
  _FakeWebSocket() : super(SolarNetworkAuthenticator(FlutterSecureStorage()));

  final packets = StreamController<WebSocketPacket>.broadcast();

  @override
  Stream<WebSocketPacket> get dataStream => packets.stream;

  @override
  Future<void> connect() async {}
}

/// Counts the reads each mail surface makes, so a realtime notice shows up as
/// a second round-trip on the surface the notice is supposed to refresh.
class _FakeMailClient extends WattEngineClient {
  _FakeMailClient() : super(SolarNetworkAuthenticator(FlutterSecureStorage()));

  int threadQueries = 0;
  int unreadQueries = 0;

  @override
  Future<PaginatedResult<MailThread>> listThreads(
    String? mailboxId, {
    String? folder,
    String? q,
    String? status,
    bool? isFlagged,
    String? from,
    String? to,
    bool? hasAttachments,
    int offset = 0,
    int take = 20,
  }) async {
    threadQueries++;
    return const PaginatedResult<MailThread>(items: [], totalCount: 0);
  }

  @override
  Future<int> listUnreadInboxCount(String mailboxId) async {
    unreadQueries++;
    return 0;
  }
}

const _query = (
  filter: (
    mailboxId: 'mb-1',
    folder: 'inbox',
    q: null,
    status: null,
    isFlagged: null,
    from: null,
    to: null,
    hasAttachments: null,
  ),
  take: 20,
);

void main() {
  test('a mail.changed packet refreshes the list and the Inbox badge', () async {
    final client = _FakeMailClient();
    final ws = _FakeWebSocket();
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith((ref) async => null),
        wattEngineClientProvider.overrideWith((ref) => client),
        websocketServiceProvider.overrideWith((ref) => ws),
        mailboxesProvider.overrideWith((ref) async => const [_mailboxWork]),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(ws.packets.close);

    // Both surfaces stay listened: an auto-disposed provider would refetch on
    // the next read regardless and hide a missing invalidation.
    container.listen(threadsProvider(_query), (_, _) {});
    container.listen(mailboxUnreadCountsProvider, (_, _) {});
    await container.read(threadsProvider(_query).future);
    await container.read(mailboxUnreadCountsProvider.future);
    expect((client.threadQueries, client.unreadQueries), (1, 1));

    // The bridge is what turns a gateway packet into those invalidations.
    final bridge = container.read(realtimeBridgeProvider);
    addTearDown(bridge.dispose);

    ws.packets.add(
      const WebSocketPacket(
        type: 'mail.changed',
        data: {'mailbox_id': 'mb-1', 'reason': 'mail.created'},
      ),
    );
    // The bridge debounces mail refreshes by 200ms.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect((client.threadQueries, client.unreadQueries), (2, 2));

    // Only mail traffic refreshes mail: an unrelated packet leaves the surfaces
    // exactly as they were.
    ws.packets.add(const WebSocketPacket(type: 'unknown.thing'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect((client.threadQueries, client.unreadQueries), (2, 2));
  });
}
