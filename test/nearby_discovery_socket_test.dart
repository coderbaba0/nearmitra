import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:farmitra_nearby/services/nearby_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DiscoverySocket extends Stream<RawSocketEvent>
    implements RawDatagramSocket {
  final events = StreamController<RawSocketEvent>();
  final datagrams = <Datagram>[];
  bool closed = false;
  @override
  bool broadcastEnabled = false;
  @override
  int multicastHops = 1;

  @override
  void joinMulticast(InternetAddress group, [NetworkInterface? interface]) {}
  @override
  int send(List<int> buffer, InternetAddress address, int port) =>
      buffer.length;
  @override
  Datagram? receive() => datagrams.isEmpty ? null : datagrams.removeAt(0);
  @override
  void close() {
    closed = true;
    unawaited(events.close());
  }

  @override
  StreamSubscription<RawSocketEvent> listen(
          void Function(RawSocketEvent)? onData,
          {Function? onError,
          void Function()? onDone,
          bool? cancelOnError}) =>
      events.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Async network loss is handled and the next announcement rebinds',
      () async {
    SharedPreferences.setMockInitialValues({});
    final first = _DiscoverySocket();
    final recovered = _DiscoverySocket();
    var binds = 0;
    final service = NearbyService(
        deviceId: 'me',
        deviceName: 'Phone',
        discoverySocketFactory: () async => ++binds == 1 ? first : recovered);
    try {
      await service.announce();
      // Android reports UDP send errors on the socket stream, after send returns.
      first.events.addError(const SocketException('Network is unreachable'));
      await Future<void>.delayed(Duration.zero);
      expect(first.closed, isTrue);
      await service.announce();
      expect(binds, 2);
      expect(recovered.closed, isFalse);
      recovered.datagrams.add(Datagram(
          utf8.encode(jsonEncode({'id': 'peer', 'name': 'Recovered peer'})),
          InternetAddress('127.0.0.2'),
          discoveryPort));
      recovered.events.add(RawSocketEvent.read);
      await Future<void>.delayed(Duration.zero);
      expect(service.getPeer('peer')?.name, 'Recovered peer');
    } finally {
      first.close();
      recovered.close();
      service.dispose();
    }
  });

  test('A closed discovery stream is rebound for later announcements',
      () async {
    SharedPreferences.setMockInitialValues({});
    final first = _DiscoverySocket();
    final recovered = _DiscoverySocket();
    var binds = 0;
    final service = NearbyService(
        deviceId: 'me',
        deviceName: 'Phone',
        discoverySocketFactory: () async => ++binds == 1 ? first : recovered);
    try {
      await service.announce();
      await first.events.close();
      await service.announce();
      expect(binds, 2);
    } finally {
      first.close();
      recovered.close();
      service.dispose();
    }
  });
}
