class TransferState {
  const TransferState({
    this.active = false,
    this.peerId,
    this.label = 'Ready',
    this.progress = 0,
    this.speedBytesPerSec = 0,
    this.etaSeconds,
  });

  final bool active;
  final String? peerId;
  final String label;
  final double progress;
  final double speedBytesPerSec;
  final int? etaSeconds;

  TransferState copyWith({
    bool? active,
    String? peerId,
    String? label,
    double? progress,
    double? speedBytesPerSec,
    int? etaSeconds,
  }) {
    return TransferState(
      active: active ?? this.active,
      peerId: peerId ?? this.peerId,
      label: label ?? this.label,
      progress: progress ?? this.progress,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      etaSeconds: etaSeconds ?? this.etaSeconds,
    );
  }
}
