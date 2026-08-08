import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/splash_screen.dart';
import 'services/device_identity.dart';
import 'services/nearby_service.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final identity = DeviceIdentity();
  final id = await identity.getId();
  final name = await identity.getName();
  runApp(FarmitraNearbyApp(service: NearbyService(deviceId: id, deviceName: name)));
}

class FarmitraNearbyApp extends StatelessWidget {
  const FarmitraNearbyApp({super.key, required this.service});

  final NearbyService service;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF169B62);
    final light = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final dark = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, child) {
        return MaterialApp(
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
