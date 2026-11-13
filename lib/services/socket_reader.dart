import 'dart:async';
import 'dart:collection';
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
  final Queue<Uint8List> _chunks = Queue<Uint8List>();
  int _offset = 0;
  int _bufferedBytes = 0;
  bool _paused = false;
  static const _highWaterMark = 1024 * 1024;
  static const _lowWaterMark = _highWaterMark ~/ 2;
  Completer<void>? _waiter;
  bool _done = false;
  Object? _error;

  Future<void> cancel() async {
    await _subscription.cancel();
    _done = true;
    _chunks.clear();
    _bufferedBytes = 0;
    _offset = 0;
    _wake();
  }

  void _onData(Uint8List data) {
    if (data.isEmpty) return;
    _chunks.add(data);
    _bufferedBytes += data.length;
    if (!_paused && _bufferedBytes >= _highWaterMark) {
      _paused = true;
      _subscription.pause();
    }
    _wake();
  }

  Uint8List _take(int count) {
    final first = _chunks.first;
    final available = first.length - _offset;
    final length = count < available ? count : available;
    final bytes = Uint8List.sublistView(first, _offset, _offset + length);
    _offset += length;
    _bufferedBytes -= length;
    if (_offset == first.length) {
      _chunks.removeFirst();
      _offset = 0;
    }
    if (_paused && _bufferedBytes <= _lowWaterMark) {
      _paused = false;
      _subscription.resume();
    }
    return bytes;
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
    final line = BytesBuilder(copy: false);
    while (true) {
      while (_chunks.isNotEmpty) {
        final first = _chunks.first;
        final newline = first.indexOf(10, _offset);
        if (newline >= 0) {
          final length = newline - _offset;
          if (length > 0) line.add(_take(length));
          _take(1);
          return utf8.decode(line.takeBytes()).trimRight();
        }
        line.add(_take(first.length - _offset));
      }
      if (_done) {
        if (_error != null) throw _error!;
        if (line.isEmpty) return null;
        return utf8.decode(line.takeBytes()).trimRight();
      }
      await _wait();
    }
  }

  Future<List<int>> readBytes(int maxBytes) async {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    while (_chunks.isEmpty && !_done) {
      await _wait();
    }
    if (_chunks.isEmpty) {
      if (_error != null) throw _error!;
      return const [];
    }
    return _take(maxBytes);
  }
}
