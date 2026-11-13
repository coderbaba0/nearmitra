import 'dart:async';

/// Starts Internet presence independently of the currently visible screen.
/// Failed initialization is retried without delaying local-network startup.
class InternetPresenceStartup {
  InternetPresenceStartup({
    required this.initialize,
    required this.restoreMode,
    required this.onError,
    this.retryDelay = const Duration(seconds: 15),
  });

  final Future<void> Function() initialize;
  final Future<void> Function() restoreMode;
  final void Function(Object) onError;
  final Duration retryDelay;
  Future<void>? _pending;
  Timer? _retry;
  bool _disposed = false;

  Future<void> ensureStarted() {
    if (_disposed) return Future<void>.value();
    return _pending ??= _start().whenComplete(() => _pending = null);
  }

  Future<void> _start() async {
    _retry?.cancel();
    try {
      await initialize();
      if (!_disposed) await restoreMode();
    } catch (error) {
      onError(error);
      if (!_disposed) {
        _retry = Timer(retryDelay, () => unawaited(ensureStarted()));
      }
    }
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
  }
}
