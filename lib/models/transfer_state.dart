class TransferState {
  const TransferState({
    this.active = false,
    this.label = 'Ready',
    this.progress = 0,
    this.speedBytesPerSec = 0,
    this.etaSeconds,
  });

  final bool active;
  final String label;
  final double progress;
  final double speedBytesPerSec;
  final int? etaSeconds;

  TransferState copyWith({
    bool? active,
    String? label,
    double? progress,
    double? speedBytesPerSec,
    int? etaSeconds,
  }) {
    return TransferState(
      active: active ?? this.active,
      label: label ?? this.label,
      progress: progress ?? this.progress,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      etaSeconds: etaSeconds,
    );
  }
}
