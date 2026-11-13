import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmitra_nearby/screens/stream_hub_screen.dart';
import 'package:farmitra_nearby/services/nearby_service.dart';
import 'package:farmitra_nearby/models/peer.dart';
import 'package:farmitra_nearby/services/wireless_audio_service.dart';
import 'package:farmitra_nearby/services/streaming_service.dart';
import 'package:farmitra_nearby/widgets/wireless_audio_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const webrtc = MethodChannel('FlutterWebRTC.Method');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var textureId = 0;
  final calls = <MethodCall>[];
  Completer<Map<String, dynamic>>? pendingRenderer;
  Completer<Map<String, dynamic>>? pendingCamera;
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

  setUp(() {
    textureId = 0;
    calls.clear();
    pendingRenderer = null;
    pendingCamera = null;
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(permissions,
        (call) async => call.method == 'requestPermissions' ? {1: 1, 7: 1} : 1);
    messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    messenger.setMockMethodCallHandler(webrtc, (call) async {
      calls.add(call);
      if (call.method == 'getUserMedia') return pendingCamera?.future;
      if (call.method == 'createVideoRenderer') {
        final id = textureId++;
        messenger.setMockMethodCallHandler(
            MethodChannel('FlutterWebRTC/Texture$id'), (_) async => null);
        return pendingRenderer?.future ?? {'textureId': id};
      }
      return null;
    });
  });

  testWidgets(
      'Closing streaming during renderer initialization releases it safely',
      (tester) async {
    final service = NearbyService(deviceId: 'test', deviceName: 'Test phone');
    pendingRenderer = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: StreamHubScreen(service: service))));
    await tester.pump();
    expect(calls.where((call) => call.method == 'createVideoRenderer'),
        hasLength(1));
    await tester.pumpWidget(const SizedBox());
    pendingRenderer!.complete({'textureId': 0});
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(calls.map((call) => call.method), contains('videoRendererDispose'));
    service.wirelessAudio.dispose();
    service.dispose();
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(permissions, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), null);
    messenger.setMockMethodCallHandler(webrtc, null);
    for (var id = 0; id < textureId; id++) {
      messenger.setMockMethodCallHandler(
          MethodChannel('FlutterWebRTC/Texture$id'), null);
    }
  });

  testWidgets(
      'Late camera capture after Back stops tracks and releases the stream',
      (tester) async {
    final service = NearbyService(deviceId: 'test', deviceName: 'Test phone');
    await StreamingService().setAllowCamera(true);
    pendingCamera = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: StreamHubScreen(
                service: service, initialStreamType: 'camera'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Host Camera (CCTV)'));
    await tester.pump();
    expect(calls.where((call) => call.method == 'getUserMedia'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    pendingCamera!.complete({
      'streamId': 'late-camera',
      'audioTracks': <Map<String, dynamic>>[],
      'videoTracks': [
        {
          'id': 'late-track',
          'label': 'camera',
          'kind': 'video',
          'enabled': true
        },
      ],
    });
    for (var turn = 0; turn < 3; turn++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(
        calls.where((call) =>
            call.method == 'trackDispose' &&
            call.arguments['trackId'] == 'late-track'),
        hasLength(1));
    expect(
        calls.where((call) =>
            call.method == 'streamDispose' &&
            call.arguments['streamId'] == 'late-camera'),
        hasLength(1));
    await StreamingService().setAllowCamera(false);
    service.wirelessAudio.dispose();
    service.dispose();
  });

  testWidgets('Reopening streaming preserves the active earpiece output',
      (tester) async {
    final service = NearbyService(deviceId: 'test', deviceName: 'Test phone');
    final audio = service.wirelessAudio;
    audio.session = WirelessAudioSession('existing-session',
        Peer(id: 'pc', name: 'PC', ip: '192.168.1.2'), 'system')
      ..live = true;
    audio.speakerEnabled = false;
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      home: StreamHubScreen(service: service, initialStreamType: 'wireless'),
    )));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'enableSpeakerphone'), isEmpty);
    expect(audio.speakerEnabled, isFalse);
    expect(find.text('Use speaker'), findsOneWidget);
    expect(find.text('Use earpiece'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await audio.stop(notify: false);
    audio.dispose();
    service.dispose();
  });

  for (final entry in {
    'camera': 1,
    'wireless': 0,
    'audio': 2,
    'screen': 3,
    'security': 4,
  }.entries) {
    testWidgets('Remote streaming opens the requested ${entry.key} tab',
        (tester) async {
      final service = NearbyService(deviceId: 'test', deviceName: 'Test phone');
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: entry.key == 'wireless'
                  ? StreamHubScreen(service: service)
                  : StreamHubScreen(
                      service: service, initialStreamType: entry.key))));
      await tester.pumpAndSettle();
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabs.controller!.index, entry.value);
      expect(tester.widget<TabBarView>(find.byType(TabBarView)).controller,
          same(tabs.controller));
      final labels = tabs.tabs.map((tab) =>
          ((tab as Tab).child! as Row).children.whereType<Text>().single.data);
      expect(labels, [
        'Wi-Fi Audio',
        'Camera CCTV',
        'Live Audio',
        'Screen Cast',
        'Security'
      ]);
      if (entry.key == 'camera') {
        await tester.tap(find.text('Wi-Fi Audio'));
        await tester.pumpAndSettle();
        expect(find.byType(WirelessAudioPanel), findsOneWidget);
        expect(find.text('Connection'), findsOneWidget);
      }
      if (entry.key == 'wireless') {
        expect(find.byType(WirelessAudioPanel), findsOneWidget);
        expect(find.text('Connection'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      service.wirelessAudio.dispose();
      service.dispose();
    });
  }
}
