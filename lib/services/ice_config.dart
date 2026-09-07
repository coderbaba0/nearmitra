class IceConfig {
  /// Robust, multi-tier STUN and TURN server configuration for NAT traversal
  /// across mobile data (CGNAT/Symmetric NAT), Wi-Fi, and cross-carrier networks.
  static const List<Map<String, dynamic>> defaultIceServers = [
    // 1. Google Public STUN Cluster (Global Anycast, Ultra-Fast UDP)
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun3.l.google.com:19302'},
    {'urls': 'stun:stun4.l.google.com:19302'},

    // 2. Cloudflare & Global STUN
    {'urls': 'stun:stun.cloudflare.com:3478'},
    {'urls': 'stun:stun.services.mozilla.com:3478'},
    {'urls': 'stun:stun.matrix.org:3478'},
    {'urls': 'stun:stun.nextcloud.com:443'},
    {'urls': 'stun:stun.sipgate.net:3478'},
    {'urls': 'stun:stun.relay.metered.ca:80'},

    // 3. OpenRelay / Metered TURN Relays (Separated per transport & port for libwebrtc parsing)
    {
      'urls': 'turn:openrelay.metered.ca:80',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:80?transport=tcp',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:3478',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:3478?transport=tcp',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turns:openrelay.metered.ca:443?transport=tcp',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turns:openrelay.metered.ca:5349?transport=tcp',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },

    // 4. FreeTurn Public Relays for Symmetric NAT Traversal
    {
      'urls': 'turn:freeturn.net:3478',
      'username': 'free',
      'credential': 'free',
    },
    {
      'urls': 'turn:freeturn.net:3478?transport=tcp',
      'username': 'free',
      'credential': 'free',
    },
    {
      'urls': 'turns:freeturn.net:5349?transport=tcp',
      'username': 'free',
      'credential': 'free',
    },
  ];

  static Map<String, dynamic> getRtcConfiguration({List<Map<String, dynamic>>? customIceServers}) {
    return {
      'iceServers': customIceServers ?? defaultIceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'iceCandidatePoolSize': 10,
      'iceTransportPolicy': 'all',
    };
  }

  static const Map<String, dynamic> peerConnectionConstraints = {
    'mandatory': <String, dynamic>{
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': <Map<String, dynamic>>[
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  static const Map<String, dynamic> offerConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };
}
