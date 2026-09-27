import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solwatt/core/services/app_icon_service.dart';

const _channel = MethodChannel('dev.solsynth.solarwatt/app_icon');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reports the alternate icon the runner has active', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          expect(call.method, 'getIconState');
          return {'supported': true, 'current': AppIconService.cuiteIconName};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );

    final state = await AppIconService.instance.getState();
    expect(state?.iconName, AppIconService.cuiteIconName);
    expect(state?.isPrimary, isFalse);
    // The surface that shows the icon maps that name to this artwork.
    expect(AppIconService.cuiteIconAsset, 'assets/icons/app-icon-cuite.png');
  });

  test('reports the primary icon when the runner has none active', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          return {'supported': true, 'current': null};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );

    final state = await AppIconService.instance.getState();
    expect(state?.isPrimary, isTrue);
    expect(AppIconService.defaultIconAsset, 'assets/icons/app-icon-default.png');
  });

  test('survives a runner that has no icon channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);

    // The channel is answered with MissingPluginException when the host has no
    // runner for it (a test host, or a platform whose runner predates the
    // channel); the caller keeps the primary artwork instead of failing.
    expect(await AppIconService.instance.getState(), isNull);
  });
}
