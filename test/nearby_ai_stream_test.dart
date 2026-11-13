import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:farmitra_nearby/models/peer.dart';
import 'package:farmitra_nearby/services/nearby_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:farmitra_nearby/services/socket_reader.dart';

final class NativeSockets extends IOOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> withHost(Future<void> Function(Socket) handle,
      Future<void> Function(NearbyService, Peer) run) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final connections = <Socket>[];
    final tasks = <Future<void>>[];
    server.listen((socket) {
      connections.add(socket);
      tasks.add(handle(socket));
    });
    final service = NearbyService(deviceId: 'phone-test', deviceName: 'Phone');
    final peer = Peer(id: 'desktop', name: 'PC', ip: '127.0.0.1');
    try {
      await IOOverrides.runZoned(() => run(service, peer), socketConnect:
          (host, port, {sourceAddress, sourcePort = 0, timeout}) {
        return NativeSockets().socketConnect(
            InternetAddress.loopbackIPv4, server.port,
            timeout: timeout);
      });
    } finally {
      for (final socket in connections) {
        socket.destroy();
      }
      await server.close();
      service.dispose();
      await Future.wait(tasks);
    }
  }

  test(
      'Windows AI loading heartbeat and real chunks reach the phone before done',
      () async {
    final allowDone = Completer<void>(), firstChunk = Completer<void>();
    await withHost((socket) async {
      final line = (await SocketReader(socket).readLine())!;
      expect((jsonDecode(line) as Map)['type'], 'ai_chat');
      socket.write('{"type":"ai_stream","status":"loading","done":false}\n');
      socket.write('{"type":"ai_stream","reply":"Hello ","done":false}\n');
      await socket.flush();
      await allowDone.future;
      socket.write(
          '{"type":"ai_stream","reply":"phone","done":false}\n{"status":"done","done":true}\n');
      await socket.flush();
    }, (service, peer) async {
      final chunks = <String>[];
      final reading = service.streamAiPrompt(peer, 'Hello').forEach((chunk) {
        chunks.add(chunk);
        if (!firstChunk.isCompleted) firstChunk.complete();
      });
      await firstChunk.future.timeout(const Duration(seconds: 3));
      expect(chunks, ['Hello ']);
      allowDone.complete();
      await reading.timeout(const Duration(seconds: 3));
      expect(chunks.join(), 'Hello phone');
    });
  });
  test('Permission denial remains visible instead of silently using local AI',
      () async {
    await withHost((socket) async {
      await SocketReader(socket).readLine();
      socket.write(
          '{"status":"disabled","reply":"PC owner has not allowed this phone","done":true}\n');
      await socket.flush();
    }, (service, peer) async {
      expect(
          await service
              .streamAiPrompt(peer, 'Hello')
              .join()
              .timeout(const Duration(seconds: 3)),
          contains('PC owner has not allowed'));
    });
  });
  test(
      'A cut-off answer remains visible with an explicit incomplete response message',
      () async {
    await withHost((socket) async {
      await SocketReader(socket).readLine();
      socket.write(
          '{"type":"ai_stream","reply":"Partial answer","done":false}\n');
      await socket.flush();
      await socket.close();
    }, (service, peer) async {
      final answer = await service
          .streamAiPrompt(peer, 'Hello')
          .join()
          .timeout(const Duration(seconds: 3));
      expect(answer, startsWith('Partial answer'));
      expect(answer, contains('before the answer was complete'));
    });
  });
  test(
      'Cancelling a mobile AI request releases its socket without replaying the prompt',
      () async {
    final cancel = Completer<void>(), peerClosed = Completer<void>();
    var requests = 0;
    await withHost((socket) async {
      requests++;
      final reader = SocketReader(socket);
      await reader.readLine();
      socket.write('{"type":"ai_stream","reply":"First","done":false}\n');
      await socket.flush();
      expect(
          await reader.readLine().timeout(const Duration(seconds: 3)), isNull);
      await reader.cancel();
      peerClosed.complete();
    }, (service, peer) async {
      final chunks = <String>[];
      await service
          .streamAiPrompt(peer, 'Hello', cancelled: cancel.future)
          .forEach((chunk) {
        chunks.add(chunk);
        cancel.complete();
      });
      await peerClosed.future.timeout(const Duration(seconds: 3));
      expect(chunks, ['First']);
      expect(requests, 1);
    });
  });
}
