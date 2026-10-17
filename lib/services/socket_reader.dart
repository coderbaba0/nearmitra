import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class SocketReader {
  SocketReader(this.socket) {
    _subscription = socket.listen(
      _onData,
      onError: (Object e, StackTrace s) {
        _error = e;
        _done = true;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
      cancelOnError: false,
    );
  }

  final Socket socket;
  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _buffer = [];
  Completer<void>? _waiter;
  bool _done = false;
  Object? _error;

  Future<void> cancel() async {
    await _subscription.cancel();
  }

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    _wake();
  }

  void _wake() {
    if (_waiter != null && !_waiter!.isCompleted) _waiter!.complete();
    _waiter = null;
  }

  Future<void> _wait() async {
    if (_done) return;
    _waiter ??= Completer<void>();
    await _waiter!.future;
    if (_error != null) throw _error!;
  }

  Future<String?> readLine() async {
    while (true) {
      final i = _buffer.indexOf(10);
      if (i >= 0) {
        final bytes = _buffer.sublist(0, i);
        _buffer.removeRange(0, i + 1);
        return utf8.decode(bytes).trimRight();
      }
      if (_done) {
        if (_buffer.isEmpty) return null;
        final bytes = List<int>.from(_buffer);
        _buffer.clear();
        return utf8.decode(bytes).trimRight();
      }
      await _wait();
    }
  }

  Future<List<int>> readBytes(int maxBytes) async {
    while (_buffer.isEmpty && !_done) {
      await _wait();
    }
    if (_buffer.isEmpty) return const [];
    final count = _buffer.length < maxBytes ? _buffer.length : maxBytes;
    final out = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return out;
  }
}
