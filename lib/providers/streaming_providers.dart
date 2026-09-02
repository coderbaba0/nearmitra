import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/streaming_service.dart';

/// Reactive provider for StreamingService
final streamingServiceProvider = ChangeNotifierProvider<StreamingService>((ref) {
  return StreamingService();
});

/// Reactive provider for trusted devices set
final trustedDevicesProvider = Provider<Set<String>>((ref) {
  final service = ref.watch(streamingServiceProvider);
  return service.trustedDevices;
});
