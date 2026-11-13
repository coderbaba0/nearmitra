import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'services/ai_settings_service.dart';
import 'services/call_service.dart';
import 'services/device_identity.dart';
import 'services/nearby_service.dart';
import 'services/streaming_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/internet_device_identity_service.dart';
import 'services/firebase_presence_service.dart';
import 'services/internet_presence_startup.dart';
import 'services/wan_service.dart';
import 'services/network_runtime.dart';
import 'services/runtime_ui_attachment.dart';
import 'providers/conversation_providers.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final backgroundStartup = args.contains('--background');

  // 1. Load saved theme mode from local storage
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('app_theme_mode');
    if (savedTheme == 'dark') {
      themeNotifier.value = ThemeMode.dark;
    } else if (savedTheme == 'light') {
      themeNotifier.value = ThemeMode.light;
    } else {
      themeNotifier.value = ThemeMode.system;
    }
  } catch (_) {}

  // 2. Initialize local AI settings, calls, streaming & identity (100% offline-ready)
  try {
    await AiSettingsService().load();
    await CallService().init();
    await StreamingService().init();
  } catch (e) {
    debugPrint('[Startup] Local services warning: $e');
  }

  final identity = DeviceIdentity();
  final id = await identity.getId();
  final name = await identity.getName();
  final emoji = await identity.getAvatarEmoji();

  final service =
      NearbyService(deviceId: id, deviceName: name, avatarEmoji: emoji);
  final lifecycle = WidgetsBinding.instance.lifecycleState;
  final runtime = NetworkRuntime.forService(service,
      foreground: lifecycle == AppLifecycleState.resumed ||
          (!backgroundStartup && lifecycle == null));

  final ui = RuntimeUiAttachment(mount: () {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    runApp(
      ProviderScope(
        overrides: [
          conversationControllerProvider
              .overrideWith((ref) => runtime.conversations)
        ],
        child: FarmitraNearbyApp(service: service),
      ),
    );
    _requestForegroundPermissions();
  });
  unawaited(ui.attach(backgroundStartup: backgroundStartup));

  // Do not wait for a widget frame: no FlutterView exists on a service-only
  // process restart. Use the same queue and service when the UI later attaches.
  unawaited(runtime.start().catchError((Object error) {
    debugPrint('[Startup] Networking error: $error');
  }));

  // Initialize Firebase in background without blocking UI or offline startup
  _initFirebaseInBackground(name, emoji);
}

void _requestForegroundPermissions() {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}

    try {
      const channel = MethodChannel('farmitra_nearby/network');
      await channel.invokeMethod('requestFullScreenIntentPermission');
    } catch (_) {}
  });
}

InternetPresenceStartup? _internetPresenceStartup;

Future<void> ensureInternetPresence() =>
    _internetPresenceStartup?.ensureStarted() ?? Future<void>.value();

void _initFirebaseInBackground(String customName, String customEmoji) {
  _internetPresenceStartup = InternetPresenceStartup(
    initialize: () async {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
                options: DefaultFirebaseOptions.isConfigured
                    ? DefaultFirebaseOptions.currentPlatform
                    : null)
            .timeout(const Duration(seconds: 4));
      }
      await InternetDeviceIdentityService().init(
        customName: customName,
        customEmoji: customEmoji,
      );
      await FirebasePresenceService().init();
    },
    restoreMode: () => WanService().restoreInternetMode(),
    onError: (error) => debugPrint('[Firebase] Startup will retry: $error'),
  );
  unawaited(ensureInternetPresence());
}

class FarmitraNearbyApp extends StatelessWidget {
  const FarmitraNearbyApp({super.key, required this.service});

  final NearbyService service;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF169B62);
    final light =
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final dark =
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, child) {
        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Farmitra Nearby',
          themeMode: mode,
          theme: ThemeData(
            colorScheme: light,
            useMaterial3: true,
            fontFamily: 'sans-serif',
            scaffoldBackgroundColor: const Color(0xFFF7F9F8),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: light.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: dark,
            useMaterial3: true,
            fontFamily: 'sans-serif',
          ),
          // home: SplashScreen(service: service),
          home: HomeScreen(service: service),
        );
      },
    );
  }
}
