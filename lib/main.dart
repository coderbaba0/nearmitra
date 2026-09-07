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

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Initialize Firebase with generated platform options
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('[Firebase] Initialized with DefaultFirebaseOptions');
  } catch (e) {
    debugPrint('[Firebase] Init error / already initialized: $e');
  }

  // 1. Load saved theme mode from persistent storage
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

  // 2. Initialize persistent AI settings & allowed peers
  await AiSettingsService().load();

  await CallService().init();
  await StreamingService().init();
  final identity = DeviceIdentity();
  final id = await identity.getId();
  final name = await identity.getName();

  // Initialize Persistent Internet Identity & Firebase Presence Service
  try {
    await InternetDeviceIdentityService().init(customName: name);
    await FirebasePresenceService().init();
  } catch (e) {
    debugPrint('[InternetIdentity] Main init warning: $e');
  }
  runApp(
    ProviderScope(
      child: FarmitraNearbyApp(
        service: NearbyService(deviceId: id, deviceName: name),
      ),
    ),
  );

  // Request critical permissions non-blocking after first frame renders
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Fix 3a: POST_NOTIFICATIONS — Required on Android 13+ for any call/notification UI
    final notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      await Permission.notification.request();
    }

    // Fix 3b: USE_FULL_SCREEN_INTENT — Required on Android 14+ for lock screen CallKit UI
    // Without this, incoming call notification won't wake the screen when locked
    try {
      const channel = MethodChannel('farmitra_nearby/network');
      await channel.invokeMethod('requestFullScreenIntentPermission');
    } catch (_) {
      // Non-critical — CallKit will still show as heads-up notification
    }
  });
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
