import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:farmitra_nearby/services/socket_reader.dart';
import 'package:flutter_test/flutter_test.dart';

class BufferedTestSocket implements Socket {
  final controller = StreamController<Uint8List>();

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      controller.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Slow file reader pauses input and resumes without losing payload bytes',
      () async {
    final socket = BufferedTestSocket();
    final reader = SocketReader(socket);
    const chunkSize = 64 * 1024;
    const chunkCount = 48;
    try {
      for (var i = 0; i < chunkCount; i++) {
        socket.controller.add(Uint8List(chunkSize)..fillRange(0, chunkSize, i));
      }
      await Future<void>.delayed(Duration.zero);
      expect(socket.controller.isPaused, isTrue,
          reason: 'A slow consumer must not buffer the entire transfer');
      var count = 0;
      while (count < chunkSize * chunkCount) {
        final bytes = await reader.readBytes(32 * 1024);
        expect(bytes.every((b) => b == count ~/ chunkSize), isTrue);
        count += bytes.length;
      }
      expect(count, chunkSize * chunkCount);
      expect(socket.controller.isPaused, isFalse);
    } finally {
      await reader.cancel();
      await socket.controller.close();
    }
  });

  test('Cancelling a reader wakes a pending read', () async {
    final socket = BufferedTestSocket();
    final reader = SocketReader(socket);
    final pending = reader.readLine();
    await reader.cancel();
    expect(await pending, isNull);
    await socket.controller.close();
  });

  test('Lines across many chunks leave the following file payload intact',
      () async {
    final socket = BufferedTestSocket();
    final reader = SocketReader(socket);
    try {
      for (final text in ['{"type":', '"file"', '}\r', '\nabc', '\nnext\n']) {
        socket.controller.add(Uint8List.fromList(utf8.encode(text)));
      }
      expect(await reader.readLine(), '{"type":"file"}');
      expect(utf8.decode(await reader.readBytes(3)), 'abc');
      expect(await reader.readLine(), '');
      expect(await reader.readLine(), 'next');
    } finally {
      await reader.cancel();
      await socket.controller.close();
    }
  });

  test(
      'A fragmented TCP header waits for its remaining bytes and retains file data',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = server.first;
    final sender =
        await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    final receiver = await accepted;
    final reader = SocketReader(receiver);
    try {
      final line = reader.readLine();
      sender.add(utf8.encode('{"type":'));
      await sender.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      sender.add(utf8.encode('"file"}\nabc'));
      await sender.flush();
      expect(await line.timeout(const Duration(seconds: 2)), '{"type":"file"}');
      expect(utf8.decode(await reader.readBytes(3)), 'abc');
    } finally {
      await reader.cancel();
      sender.destroy();
      receiver.destroy();
      await server.close();
    }
  });
}
