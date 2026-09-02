import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/peer.dart';
import '../services/nearby_service.dart';

/// Provider exposing the active NearbyService instance
final nearbyServiceProvider = ChangeNotifierProvider<NearbyService>((ref) {
  return NearbyService.instance;
});

/// Reactive provider for the active online peers list
final activePeersProvider = Provider<List<Peer>>((ref) {
  final service = ref.watch(nearbyServiceProvider);
  return service.peers;
});
