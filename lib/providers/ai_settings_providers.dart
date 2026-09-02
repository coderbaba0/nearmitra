import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ai_settings_service.dart';

/// Reactive provider for AiSettingsService
final aiSettingsServiceProvider = ChangeNotifierProvider<AiSettingsService>((ref) {
  final service = AiSettingsService();
  service.load();
  return service;
});

/// Reactive provider for the active AiConfig
final aiConfigProvider = Provider<AiConfig>((ref) {
  final service = ref.watch(aiSettingsServiceProvider);
  return service.config;
});
