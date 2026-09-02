import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/call_service.dart';

/// Provider for the singleton CallService
final callServiceProvider = Provider<CallService>((ref) {
  return CallService();
});
