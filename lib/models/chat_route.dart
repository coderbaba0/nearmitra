import 'peer.dart';
import 'wan_models.dart';

enum ChatTransport { nearby, internet, offline }

/// Resolves transport independently of the discovery tab being displayed.
class ChatRoute {
  const ChatRoute(
      {required this.peer,
      this.nearby,
      this.internet,
      required this.transport});

  final Peer peer;
  final Peer? nearby;
  final WanDevice? internet;
  final ChatTransport transport;

  bool get canCall =>
      transport == ChatTransport.nearby &&
      nearby != null &&
      !nearby!.isMeshPeer;

  static ChatRoute resolve(Peer peer, List<Peer> nearbyPeers,
      List<WanDevice> internetPeers, Map<String, String> links,
      {required bool internetEnabled, String? connectedInternetPeerId}) {
    String canonical(String id) => links[id] ?? id;
    final id = canonical(peer.id);
    Peer? local;
    for (final candidate in nearbyPeers) {
      if (canonical(candidate.id) == id || candidate.internetDeviceId == id ||
          (peer.internetDeviceId != null && candidate.internetDeviceId == peer.internetDeviceId) ||
          (peer.ip.isNotEmpty && candidate.ip == peer.ip && !candidate.isMeshPeer)) {
        if (candidate.isOnline && candidate.ip.isNotEmpty) local = candidate;
      }
    }
    WanDevice? remote;
    for (final candidate in internetPeers) {
      if (candidate.id == id || candidate.id == peer.internetDeviceId) {
        remote = candidate;
        break;
      }
    }
    return ChatRoute(
      peer: peer,
      nearby: local,
      internet: remote,
      transport: local != null
          ? ChatTransport.nearby
          : internetEnabled &&
                  remote != null &&
                  remote.isTrusted &&
                  (remote.isOnline || remote.id == connectedInternetPeerId)
              ? ChatTransport.internet
              : ChatTransport.offline,
    );
  }
}
