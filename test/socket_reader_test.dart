import 'dart:convert';
import 'dart:io';

import 'package:farmitra_nearby/services/socket_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
