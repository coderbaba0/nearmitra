import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmitra_nearby/models/peer.dart';
import 'package:farmitra_nearby/services/nearby_service.dart';
import 'package:farmitra_nearby/widgets/wireless_audio_panel.dart';
import 'package:farmitra_nearby/widgets/wireless_audio_meter.dart';

class PanelService extends NearbyService {
  bool stale = false;
  bool hidden = false;
  PanelService() : super(deviceId: 'phone', deviceName: 'Phone');
  @override
  List<Peer> get peers => hidden
      ? []
      : [
          Peer(
              id: 'desktop',
              name: 'Windows desktop with a long device name',
              ip: '192.168.1.5',
              lastSeen: stale
                  ? DateTime.now().subtract(const Duration(minutes: 1))
                  : null)
        ];
}

void main() {
  testWidgets(
      'Selected PC stays available after its discovery heartbeat expires',
      (tester) async {
    final service = PanelService();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WirelessAudioPanel(service: service))));
    expect(find.textContaining('192.168.1.5'), findsWidgets);
    service.stale = true;
    service.hidden = true;
    service.notifyListeners();
    await tester.pump();
    expect(find.textContaining('192.168.1.5'), findsWidgets);
    final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Listen to PC audio'));
    expect(start.onPressed, isNotNull);
    expect(find.textContaining('Connect a Nearby'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
  testWidgets(
      'Audio bars respond to measured energy and return to idle after stop',
      (tester) async {
    Widget meter(double level, bool active) => MaterialApp(
        home: Scaffold(body: WirelessAudioMeter(level: level, active: active)));
    await tester.pumpWidget(meter(0, true));
    await tester.pump(const Duration(milliseconds: 300));
    final quiet = tester.getSize(find.byType(AnimatedContainer).at(7)).height;
    await tester.pumpWidget(meter(0.5, true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.byType(AnimatedContainer).at(7)).height,
        greaterThan(quiet));
    await tester.pumpWidget(meter(0.5, false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.byType(AnimatedContainer).at(7)).height, quiet);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets(
        'Wireless controls fit a narrow phone with large text (${dark ? 'dark' : 'light'})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = PanelService();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.green,
                  brightness: dark ? Brightness.dark : Brightness.light)),
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(320, 850), textScaler: TextScaler.linear(1.5)),
              child: Scaffold(body: WirelessAudioPanel(service: service)))));
      await tester.pump();
      expect(find.text('Wi-Fi Audio'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Listen to PC audio'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(find.text('Listen to PC audio'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });
  }
}
