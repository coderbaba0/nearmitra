import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmitra_nearby/models/peer.dart';
import 'package:farmitra_nearby/services/nearby_service.dart';
import 'package:farmitra_nearby/services/wireless_audio_service.dart';
import 'package:farmitra_nearby/widgets/wireless_audio_panel.dart';
import 'package:farmitra_nearby/widgets/wireless_audio_meter.dart';

class PanelService extends NearbyService {
  bool stale = false;
  bool hidden = false;
  final String? platform;
  final WirelessAudioService? testAudio;
  PanelService({this.platform, this.testAudio})
      : super(deviceId: 'phone', deviceName: 'Phone');
  @override
  WirelessAudioService get wirelessAudio => testAudio ?? super.wirelessAudio;
  @override
  List<Peer> get peers => hidden
      ? []
      : [
          Peer(
              id: 'desktop',
              name: 'Windows desktop with a long device name',
              ip: '192.168.1.5',
              platform: platform,
              lastSeen: stale
                  ? DateTime.now().subtract(const Duration(minutes: 1))
                  : null)
        ];
}

void main() {
  testWidgets(
      'Phone source offers app audio and explains Android capture consent',
      (tester) async {
    final service = PanelService(platform: 'android');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WirelessAudioPanel(service: service))));
    await tester.scrollUntilVisible(find.text('Listen to phone audio'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Listen to phone audio'), findsOneWidget);
    expect(find.text('Listen to PC audio'), findsNothing);
    expect(find.textContaining('music, video and app audio'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
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
    await tester.scrollUntilVisible(find.text('Listen to PC audio'), 200,
        scrollable: find.byType(Scrollable).first);
    final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Listen to PC audio'));
    expect(start.onPressed, isNotNull);
    expect(find.textContaining('Connect a Nearby'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
  testWidgets(
      'Colour waves keep flowing between samples and settle after silence or stop',
      (tester) async {
    Widget meter(double level, bool active) => MaterialApp(
        home: Scaffold(body: WirelessAudioMeter(level: level, active: active)));
    await tester.pumpWidget(meter(0, true));
    AudioWavePainter painter() => tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(WirelessAudioMeter),
            matching: find.byType(CustomPaint)))
        .painter! as AudioWavePainter;
    expect(painter().energy.value, 0);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(meter(0.5, true));
    await tester.pump(const Duration(milliseconds: 40));
    expect(painter().energy.value, inExclusiveRange(0, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(painter().energy.value, 0.5);
    expect(painter().colors.toSet(), hasLength(5));
    expect(tester.hasRunningAnimations, isTrue);
    final phase = painter().phase.value;
    await tester.pump(const Duration(milliseconds: 16));
    expect(painter().phase.value, isNot(phase));
    await tester.pumpWidget(meter(0.5, true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(painter().energy.value, 0.5);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(meter(0, true));
    await tester.pump(const Duration(milliseconds: 400));
    expect(painter().energy.value, 0);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(meter(0.8, true));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(meter(0.8, false));
    await tester.pump(const Duration(milliseconds: 400));
    expect(painter().energy.value, 0);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Output shows only the alternate route and waits for success',
      (tester) async {
    final routes = <bool>[];
    var pending = Completer<void>();
    var fail = false;
    final audio = WirelessAudioService(
      send: (_, __, ___) async {},
      isOccupied: () => false,
      routeOutput: (speaker) async {
        routes.add(speaker);
        await pending.future;
        if (fail) throw StateError('Output unavailable');
      },
      stopNative: () async {},
    );
    final service = PanelService(testAudio: audio);
    audio.session =
        WirelessAudioSession('live-test', service.peers.first, 'system')
          ..live = true;
    audio.status = 'Wireless audio live';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WirelessAudioPanel(service: service))));
    final output = find.byKey(const ValueKey('wireless-output-toggle'));
    await tester.ensureVisible(output);
    expect(find.text('Use earpiece'), findsOneWidget);
    expect(find.text('Use speaker'), findsNothing);
    expect(find.text('Phone speaker'), findsNothing);
    await tester.tap(output);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(output).onPressed, isNull);
    expect(find.text('Switching output…'), findsOneWidget);
    expect(routes, [false]);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Use speaker'), findsOneWidget);
    expect(find.text('Use earpiece'), findsNothing);
    pending = Completer<void>();
    fail = true;
    await tester.tap(output);
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Use speaker'), findsOneWidget);
    expect(find.textContaining('Output could not change'), findsOneWidget);
    expect(routes, [false, true]);
    pending = Completer<void>();
    fail = false;
    await tester.tap(output);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Use earpiece'), findsOneWidget);
    expect(find.text('Use speaker'), findsNothing);
    expect(find.textContaining('Output could not change'), findsNothing);
    await tester.ensureVisible(find.text('Stop wireless audio'));
    await tester.tap(find.text('Stop wireless audio'));
    await tester.pumpAndSettle();
    expect(audio.session, isNull);
    await tester.scrollUntilVisible(find.text('Listen to PC audio'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Listen to PC audio'))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
    await audio.stop(notify: false);
    audio.dispose();
    service.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Reduced motion and hidden tabs pause the flowing waves',
      (tester) async {
    Widget meter(double level, {bool reduced = true, bool visible = true}) =>
        MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: TickerMode(
                    enabled: visible,
                    child: WirelessAudioMeter(level: level, active: true))));
    await tester.pumpWidget(meter(0));
    await tester.pumpWidget(meter(0.7));
    final painter = tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(WirelessAudioMeter),
            matching: find.byType(CustomPaint)))
        .painter! as AudioWavePainter;
    expect(painter.energy.value, 0.7);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(meter(0.7, reduced: false));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(meter(0.7, reduced: false, visible: false));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(meter(0.7, reduced: false));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(meter(0.7));
    expect(tester.hasRunningAnimations, isFalse);
  });
  for (final dark in [false, true]) {
    for (final live in [false, true]) {
      testWidgets(
          'Wireless controls fit a narrow phone with large text (dark: $dark, live: $live)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final audio = WirelessAudioService(
            send: (_, __, ___) async {},
            isOccupied: () => false,
            routeOutput: (_) async {},
            stopNative: () async {});
        final service = PanelService(testAudio: audio);
        if (live) {
          audio.session =
              WirelessAudioSession('narrow-live', service.peers.first, 'system')
                ..live = true;
        }
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.green,
                    brightness: dark ? Brightness.dark : Brightness.light)),
            home: MediaQuery(
                data: const MediaQueryData(
                    size: Size(320, 850),
                    padding: EdgeInsets.only(bottom: 24),
                    textScaler: TextScaler.linear(1.5)),
                child: Scaffold(body: WirelessAudioPanel(service: service)))));
        await tester.pump();
        expect(find.text('Wi-Fi Audio'), findsOneWidget);
        final action = live ? 'Stop wireless audio' : 'Listen to PC audio';
        expect(find.text(action).hitTestable(), findsOneWidget);
        expect(
            tester.getRect(find.text(action)).bottom, lessThanOrEqualTo(826));
        expect(find.byType(WirelessAudioMeter),
            live ? findsOneWidget : findsNothing);
        await tester.scrollUntilVisible(find.text(action), 200,
            scrollable: find.byType(Scrollable).first);
        await tester.pump();
        expect(find.text(action), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await audio.stop(notify: false);
        audio.dispose();
        service.dispose();
      });
    }
  }
}
