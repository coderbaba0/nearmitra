import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:farmitra_nearby/services/nearby_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows typing start and stop update the same live phone peer', () async {
    SharedPreferences.setMockInitialValues({});
    final service = NearbyService(deviceId: 'phone', deviceName: 'Phone');
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final tasks = <Future<void>>[];
    server.listen((socket) => tasks.add(service.handleIncomingConnection(socket)));
    try {
      for (final typing in [true, false, true]) {
        final changed = Completer<void>();
        void listener() {
          if (service.peers.any((p) => p.id == 'windows' && p.isTyping == typing) &&
              !changed.isCompleted) {
            changed.complete();
          }
        }
        service.addListener(listener);
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
        try {
          socket.write('${jsonEncode({
            'type': 'typing',
            'sender_id': 'windows',
            'sender': 'Office PC',
            if (typing) 'is_typing': true,
            'message': typing.toString(),
          })}\n');
          await socket.flush();
          await changed.future.timeout(const Duration(seconds: 3));
          final peer = service.peers.singleWhere((p) => p.id == 'windows');
          expect(peer.isTyping, typing);
          expect(peer.isOnline, isTrue);
        } finally {
          service.removeListener(listener);
          socket.destroy();
        }
      }
    } finally {
      await server.close();
      await Future.wait(tasks);
      service.dispose();
    }
  });
}
