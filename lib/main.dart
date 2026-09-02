import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'services/ai_settings_service.dart';
import 'services/call_service.dart';
import 'services/device_identity.dart';
import 'services/nearby_service.dart';
import 'services/streaming_service.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

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
  runApp(
    ProviderScope(
      child: FarmitraNearbyApp(
        service: NearbyService(deviceId: id, deviceName: name),
      ),
    ),
  );
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
          home: SplashScreen(service: service),
        );
      },
    );
  }
}
