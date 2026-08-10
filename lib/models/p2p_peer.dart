class P2pPeer {
  P2pPeer({
    required this.name,
    required this.deviceAddress,
    this.status = 3,
    this.primaryDeviceType = '',
  });

  final String name;
  final String deviceAddress;
  int status;
  final String primaryDeviceType;

  factory P2pPeer.fromMap(Map<dynamic, dynamic> map) {
    return P2pPeer(
      name: map['name']?.toString() ?? 'Nearby Device',
      deviceAddress: map['address']?.toString() ?? '',
      status: (map['status'] as num?)?.toInt() ?? 3,
      primaryDeviceType: map['primaryDeviceType']?.toString() ?? '',
    );
  }

  String get statusLabel {
    switch (status) {
      case 0:
        return 'Connected';
      case 1:
        return 'Connecting…';
      case 2:
        return 'Failed';
      case 3:
        return 'Available';
      case 4:
        return 'Unavailable';
      default:
        return 'Available';
    }
  }

  bool get isConnected => status == 0;
  bool get isConnecting => status == 1;
}
